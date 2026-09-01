import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../audio/feature_extractor.dart';
import '../data/models/analysis.dart';
import '../data/models/goal.dart';
import '../data/models/provider_config.dart';
import '../data/models/recommendation.dart';
import '../data/models/segment.dart';
import '../data/models/session.dart';
import '../data/models/speaker.dart';
import '../data/repository.dart';
import '../llm/llm_provider.dart';
import '../llm/prompt_registry.dart';
import '../llm/provider_registry.dart';
import '../transcription/transcription_engine.dart';
import 'qa_service.dart';

/// Orchestrates the analysis pipeline (Tech Spec §6.1):
/// transcribe → segment → feature-extract → LLM analysis → aggregate →
/// recommend → index for Q&A. Persists everything to the encrypted store.
class AnalysisOrchestrator {
  final Repository repo;
  final ProviderRegistry providers;
  final FeatureExtractor features;
  final _uuid = const Uuid();

  AnalysisOrchestrator({
    required this.repo,
    required this.providers,
  }) : features = FeatureExtractor();

  /// Runs transcription + analysis for a recorded session, updating status as
  /// it goes so the UI can reflect progress. Returns the produced [Analysis].
  ///
  /// [providerConfig] is the user's preferred provider; if it has no usable key
  /// the registry transparently falls back to the offline demo provider so the
  /// loop still completes (bring-your-own-key with a fallback).
  Future<Analysis> run({
    required Session session,
    required Goal goal,
    required Rubric rubric,
    required TranscriptionEngine transcriptionEngine,
    required ProviderConfig providerConfig,
    required String audioPath,
  }) async {
    // 2. ASR + diarize -> timestamped, speaker-tagged transcript.
    await repo.updateSessionStatus(session.id, SessionStatus.transcribing);
    final transcript = await transcriptionEngine.transcribe(
      audioPath: audioPath,
      languages: [session.language],
    );

    // No speech captured (e.g. a silent/empty recording) — fail clearly rather
    // than running a doomed analysis on an empty transcript.
    if (transcript.turns.where((t) => t.text.trim().isNotEmpty).isEmpty) {
      throw const LLMException(
          'No speech was detected in the recording. Check that the microphone '
          'captured audio, then record again.');
    }

    // 3. Segment + persist speakers. Speaker tags map to Speaker rows; the user
    //    can rename them later (F-TRA-05).
    final speakers = await _ensureSpeakers(session.id, transcript);
    final segments = _toSegments(session.id, transcript, speakers);

    // 4. Feature extraction (dynamics + per-segment prosody).
    for (var i = 0; i < segments.length; i++) {
      final next = i + 1 < segments.length ? segments[i + 1] : null;
      segments[i].prosodyFeatures = features.prosodyFor(segments[i], next);
    }
    final speakerMap = {for (final s in speakers) s.id: s};
    final dynamics = features.computeDynamics(segments, speakerMap);

    // Index for Q&A — store a lightweight lexical embedding per segment.
    for (final s in segments) {
      s.embedding = QAService.embed(s.text);
    }
    await repo.upsertSegments(segments);

    // 5. LLM analysis (structured JSON).
    await repo.updateSessionStatus(session.id, SessionStatus.analyzing);
    final provider = await providers.resolveForAnalysis(providerConfig);

    // On-device Gemma has a small (4096-token) context window, so a long
    // meeting's full transcript overflows it ("token ids are too long
    // 16403 >= 4096"). Cap what we FEED the model — the dynamics/emotion
    // metrics above are computed from the full `segments`, so accuracy there is
    // unaffected; only the prose analysis works from a representative sample.
    final isLocal = providerConfig.provider == ProviderKind.local;
    final promptSegments =
        isLocal ? _cappedForPrompt(segments, speakerMap) : segments;

    final request = PromptRegistry.analysis(
      session: session,
      goal: goal,
      rubric: rubric,
      segments: promptSegments,
      speakers: speakerMap,
      modelOverride: providerConfig.perTaskOverrides['analysis'],
      // Small on-device models need the compact, strict-JSON prompt.
      simple: isLocal,
    );

    final response = await _completeWithRetry(provider, request);
    final parsed = _parseJson(response.text);

    // 6. Aggregate + 7. Recommend.
    final analysis = _buildAnalysis(
      session: session,
      rubric: rubric,
      dynamics: dynamics,
      parsed: parsed,
      modelUsed: response.modelUsed,
      usage: response.usage,
    );
    await repo.upsertAnalysis(analysis);

    final recs = _buildRecommendations(session.id, parsed);
    await repo.replaceRecommendations(session.id, recs);

    // Snapshot the provider+model used, for the report header (F-MOD-01).
    final updated = session
      ..providerConfigSnapshot =
          '${provider.displayName} · ${response.modelUsed}'
      ..durationSec = session.durationSec
      ..status = SessionStatus.ready;
    await repo.upsertSession(updated);

    return analysis;
  }

  /// Trims the transcript that is FED to a small on-device model so it fits the
  /// model's context window (Gemma 4 E2B: 4096 tokens). A ~9-minute meeting is
  /// ~16k tokens — far over the limit — so we evenly SAMPLE segments across the
  /// whole conversation (preserving start/middle/end coverage and chronological
  /// order) until the rendered transcript fits the character budget.
  ///
  /// [maxChars] ≈ 1.6k tokens at ~4 chars/token, leaving room for the ~0.6k
  /// system prompt and 1536 output tokens inside 4096. This only affects the
  /// prose analysis prompt; the full segment list still drives dynamics/emotion
  /// metrics and Q&A indexing, so those stay accurate on long recordings.
  List<Segment> _cappedForPrompt(
    List<Segment> segments,
    Map<String, Speaker> speakers, {
    int maxChars = 6000,
  }) {
    if (segments.isEmpty) return segments;
    final full = PromptRegistry.renderTranscript(segments, speakers);
    if (full.length <= maxChars) return segments;

    // How many segments can we keep, given the average rendered line length?
    final avgLine = full.length / segments.length;
    var keep = (maxChars / avgLine).floor();
    if (keep < 1) keep = 1;
    if (keep >= segments.length) return segments;

    // Evenly spaced pick across the timeline keeps the arc of the conversation
    // rather than just the opening minutes.
    final step = segments.length / keep;
    final picked = <Segment>[];
    final seen = <int>{};
    for (var i = 0; i < keep; i++) {
      final idx = (i * step).floor().clamp(0, segments.length - 1);
      if (seen.add(idx)) picked.add(segments[idx]);
    }
    return picked;
  }

  Future<List<Speaker>> _ensureSpeakers(
      String sessionId, TranscriptionResult t) async {
    final existing = await repo.speakers(sessionId);
    if (existing.isNotEmpty) return existing;
    final tags = <String>{for (final turn in t.turns) turn.speakerTag};
    final speakers = <Speaker>[];
    var first = true;
    for (final tag in tags) {
      final sp = Speaker(
        id: 'spk-${_uuid.v4()}',
        sessionId: sessionId,
        label: first ? 'You' : tag,
        isUser: first,
      );
      first = false;
      await repo.upsertSpeaker(sp);
      speakers.add(sp);
    }
    return speakers;
  }

  List<Segment> _toSegments(
      String sessionId, TranscriptionResult t, List<Speaker> speakers) {
    final byTag = <String, Speaker>{};
    // Map original tags back to speakers in the order they were created.
    final tagOrder = <String>{for (final turn in t.turns) turn.speakerTag}.toList();
    for (var i = 0; i < tagOrder.length && i < speakers.length; i++) {
      byTag[tagOrder[i]] = speakers[i];
    }
    return [
      for (final turn in t.turns)
        Segment(
          id: 'seg-${_uuid.v4()}',
          sessionId: sessionId,
          speakerId: (byTag[turn.speakerTag] ?? speakers.first).id,
          startMs: turn.startMs,
          endMs: turn.endMs,
          text: turn.text,
        ),
    ];
  }

  Future<PromptResponse> _completeWithRetry(
      LLMProvider provider, PromptRequest request) async {
    // Retry with backoff (Tech Spec §5 resilience).
    var attempt = 0;
    LLMException? last;
    while (attempt < 3) {
      try {
        return await provider.complete(request);
      } on LLMException catch (e) {
        last = e;
        // Don't retry auth/validation errors.
        if (e.statusCode == 401 || e.statusCode == 400) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
        attempt++;
      }
    }
    throw last ?? const LLMException('Analysis failed.');
  }

  Map<String, dynamic> _parseJson(String text) {
    Map<String, dynamic>? tryDecode(String s) {
      try {
        final v = jsonDecode(s);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    // 1. Straight JSON.
    final direct = tryDecode(text);
    if (direct != null) return direct;

    // 2. Small models often wrap JSON in ```json fences, add prose, or leave
    //    trailing commas. Strip fences, take the outermost {...}, and drop
    //    trailing commas before a } or ].
    var t = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) {
      var body = t.substring(start, end + 1);
      // Repair the small-model JSON slips seen in practice, in order:
      // 1. Missing OPENING quote on a bareword string element — a value after
      //    a `[` or `,` that starts with a letter and ends with `"`.
      body = body.replaceAllMapped(
          RegExp(r'([\[,]\s*\n\s*)([A-Za-z][^\n]*?")(\s*[,\]\n])'),
          (m) => '${m[1]}"${m[2]}${m[3]}');
      // 2. Missing commas between a value/array/object end and the next key.
      body = body.replaceAllMapped(
          RegExp(r'([}\]"\d])\s*\n(\s*")'), (m) => '${m[1]},\n${m[2]}');
      // 3. Doubled / empty commas (e.g. a stray "," on its own line).
      body = body.replaceAll(RegExp(r',(\s*,)+'), ',');
      // 4. Trailing commas before a } or ].
      body = body.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
      final parsed = tryDecode(body);
      if (parsed != null) return parsed;
    }

    // 3. Resilient fallback: the model sometimes drops a closing bracket or
    //    strews stray commas, which no comma fix can undo. Harvest each known
    //    field directly from the raw text so a structural error in one field
    //    never loses the whole analysis.
    final extracted = _extractFields(t);
    if (extracted.isNotEmpty) return extracted;

    // Include a snippet of what the model actually returned so the failure is
    // diagnosable on-device.
    final snippet =
        text.trim().isEmpty ? '(empty response)' : text.trim();
    final shown = snippet.length > 300 ? '${snippet.substring(0, 300)}…' : snippet;
    throw LLMException(
        'Could not parse analysis JSON from the on-device model. It returned:\n'
        '$shown');
  }

  /// Known top-level analysis keys, used to bound each field's span when
  /// harvesting from malformed JSON.
  static const List<String> _analysisKeys = [
    'headline', 'summary', 'topics', 'openQuestions', 'strengths',
    'improvements', 'nextSteps', 'recommendations', 'scoreOverall',
    'scoreByDimension',
  ];

  /// Harvests each known field straight from the raw model text — tolerant of
  /// missing brackets, stray commas and other structural slips that defeat a
  /// strict JSON parse. Returns whatever fields it could recover.
  Map<String, dynamic> _extractFields(String raw) {
    final map = <String, dynamic>{};

    String? scalar(String key) =>
        RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"')
            .firstMatch(raw)
            ?.group(1)
            ?.trim();

    final headline = scalar('headline');
    if (headline != null && headline.isNotEmpty) map['headline'] = headline;
    final summary = scalar('summary');
    if (summary != null && summary.isNotEmpty) map['summary'] = summary;

    final so = RegExp(r'"scoreOverall"\s*:\s*"?(\d+)').firstMatch(raw);
    if (so != null) map['scoreOverall'] = int.parse(so.group(1)!);

    // Earliest known key at/after [from] — bounds a field's text span.
    int nextKey(int from) {
      var best = raw.length;
      for (final k in _analysisKeys) {
        final i = raw.indexOf('"$k"', from);
        if (i >= 0 && i < best) best = i;
      }
      return best;
    }

    List<String> stringArray(String key) {
      final ki = raw.indexOf('"$key"');
      if (ki < 0) return const [];
      final from = ki + key.length + 2;
      final span = raw.substring(from, nextKey(from));
      return RegExp(r'"((?:[^"\\]|\\.)*)"')
          .allMatches(span)
          .map((m) => m.group(1)!.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    for (final key in const [
      'topics', 'openQuestions', 'strengths', 'improvements', 'nextSteps'
    ]) {
      final arr = stringArray(key);
      if (arr.isNotEmpty) map[key] = arr;
    }

    // scoreByDimension: pull each dimension/score/rationale triple in order.
    final di = raw.indexOf('"scoreByDimension"');
    if (di >= 0) {
      final span = raw.substring(di);
      final dims = <Map<String, dynamic>>[];
      final re = RegExp(
          r'"dimension"\s*:\s*"([^"]*)"[\s\S]*?"score"\s*:\s*"?(\d+)"?[\s\S]*?"rationale"\s*:\s*"((?:[^"\\]|\\.)*)"');
      for (final m in re.allMatches(span)) {
        dims.add({
          'dimension': m.group(1),
          'score': int.parse(m.group(2)!),
          'rationale': m.group(3),
        });
      }
      if (dims.isNotEmpty) map['scoreByDimension'] = dims;
    }

    // recommendations: pull each priority/text/(whatToTryInstead) group.
    final rci = raw.indexOf('"recommendations"');
    if (rci >= 0) {
      final span = raw.substring(rci, nextKey(rci + 17));
      final recs = <Map<String, dynamic>>[];
      final re = RegExp(
          r'"priority"\s*:\s*"?(\d+)"?[\s\S]*?"text"\s*:\s*"((?:[^"\\]|\\.)*)"(?:[\s\S]*?"whatToTryInstead"\s*:\s*"((?:[^"\\]|\\.)*)")?');
      for (final m in re.allMatches(span)) {
        recs.add({
          'priority': int.parse(m.group(1)!),
          'text': m.group(2),
          'whatToTryInstead': m.group(3),
        });
      }
      if (recs.isNotEmpty) map['recommendations'] = recs;
    }

    return map;
  }

  Analysis _buildAnalysis({
    required Session session,
    required Rubric rubric,
    required Dynamics dynamics,
    required Map<String, dynamic> parsed,
    required String modelUsed,
    required TokenUsage usage,
  }) {
    // Small models are sloppy about types: a field the schema says is a string
    // array may come back as a bare string; numbers may be strings; list items
    // may be malformed. Coerce leniently and skip anything unparseable rather
    // than failing the whole analysis.
    List<String> strs(String key) {
      final v = parsed[key];
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (v is String && v.trim().isNotEmpty) return [v.trim()];
      return const [];
    }

    List<Map<String, dynamic>> maps(String key) {
      final v = parsed[key];
      if (v is! List) return const [];
      return v.whereType<Map<String, dynamic>>().toList();
    }

    final dims = <DimensionScore>[];
    for (final m in maps('scoreByDimension')) {
      try {
        dims.add(DimensionScore.fromJson(m));
      } catch (_) {}
    }

    // Use the model's overall score if present, else compute from the rubric
    // weights as a safety net (capability negotiation / output consistency).
    final rawOverall = parsed['scoreOverall'];
    double overall = rawOverall is num
        ? rawOverall.toDouble()
        : (rawOverall is String ? (double.tryParse(rawOverall.trim()) ?? -1) : -1);
    if (overall < 0) {
      final weights = rubric.normalisedWeights();
      overall = dims.fold<double>(
          0, (sum, d) => sum + d.score * (weights[d.dimension] ?? 0));
    }

    final arc = <EmotionPoint>[];
    for (final m in maps('emotionArc')) {
      try {
        arc.add(EmotionPoint.fromJson(m));
      } catch (_) {}
    }

    return Analysis(
      id: 'an-${_uuid.v4()}',
      sessionId: session.id,
      headline: (parsed['headline'] ?? '').toString(),
      summary: (parsed['summary'] ?? '').toString(),
      topics: strs('topics'),
      decisions: strs('decisions'),
      actionItems: strs('actionItems'),
      openQuestions: strs('openQuestions'),
      strengths: strs('strengths'),
      improvements: strs('improvements'),
      nextSteps: strs('nextSteps'),
      dynamics: dynamics,
      scoreOverall: overall.clamp(0, 100),
      scoreByDimension: dims,
      emotionArc: arc,
      modelUsed: modelUsed,
      promptVersion: PromptRegistry.version,
      createdAt: DateTime.now(),
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
    );
  }

  List<Recommendation> _buildRecommendations(
      String sessionId, Map<String, dynamic> parsed) {
    final raw = parsed['recommendations'];
    final list = raw is List
        ? raw.whereType<Map<String, dynamic>>()
        : const <Map<String, dynamic>>[];
    final recs = <Recommendation>[];
    var i = 0;
    for (final m in list) {
      i++;
      final p = m['priority'];
      final priority = p is num
          ? p.toInt()
          : (p is String ? (int.tryParse(p.trim()) ?? i) : i);
      final text = (m['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final ev = m['evidenceRefs'] ?? m['evidenceSegmentIds'];
      final tryInstead = m['whatToTryInstead'];
      recs.add(Recommendation(
        id: 'rec-${_uuid.v4()}',
        sessionId: sessionId,
        priority: priority,
        text: text,
        evidenceRefs: ev is List ? ev.map((e) => e.toString()).toList() : const [],
        whatToTryInstead: tryInstead == null ? null : tryInstead.toString(),
      ));
    }
    return recs;
  }
}

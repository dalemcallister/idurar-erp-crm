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

    final request = PromptRegistry.analysis(
      session: session,
      goal: goal,
      rubric: rubric,
      segments: segments,
      speakers: speakerMap,
      modelOverride: providerConfig.perTaskOverrides['analysis'],
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
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      // Tolerate models that wrap JSON in prose/fences — extract the object.
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(text.substring(start, end + 1))
              as Map<String, dynamic>;
        } catch (_) {}
      }
      throw const LLMException('Could not parse analysis JSON from the model.');
    }
  }

  Analysis _buildAnalysis({
    required Session session,
    required Rubric rubric,
    required Dynamics dynamics,
    required Map<String, dynamic> parsed,
    required String modelUsed,
  }) {
    List<String> strs(String key) =>
        ((parsed[key] as List?) ?? const []).map((e) => e.toString()).toList();

    final dims = ((parsed['scoreByDimension'] as List?) ?? const [])
        .map((e) => DimensionScore.fromJson(e as Map<String, dynamic>))
        .toList();

    // Use the model's overall score if present, else compute from the rubric
    // weights as a safety net (capability negotiation / output consistency).
    double overall = (parsed['scoreOverall'] as num?)?.toDouble() ?? -1;
    if (overall < 0) {
      final weights = rubric.normalisedWeights();
      overall = dims.fold<double>(
          0, (sum, d) => sum + d.score * (weights[d.dimension] ?? 0));
    }

    final arc = ((parsed['emotionArc'] as List?) ?? const [])
        .map((e) => EmotionPoint.fromJson(e as Map<String, dynamic>))
        .toList();

    return Analysis(
      id: 'an-${_uuid.v4()}',
      sessionId: session.id,
      headline: (parsed['headline'] as String?) ?? '',
      summary: (parsed['summary'] as String?) ?? '',
      topics: strs('topics'),
      decisions: strs('decisions'),
      actionItems: strs('actionItems'),
      openQuestions: strs('openQuestions'),
      strengths: strs('strengths'),
      improvements: strs('improvements'),
      dynamics: dynamics,
      scoreOverall: overall.clamp(0, 100),
      scoreByDimension: dims,
      emotionArc: arc,
      modelUsed: modelUsed,
      promptVersion: PromptRegistry.version,
      createdAt: DateTime.now(),
    );
  }

  List<Recommendation> _buildRecommendations(
      String sessionId, Map<String, dynamic> parsed) {
    final list = (parsed['recommendations'] as List?) ?? const [];
    final recs = <Recommendation>[];
    var i = 0;
    for (final r in list) {
      final m = r as Map<String, dynamic>;
      recs.add(Recommendation(
        id: 'rec-${_uuid.v4()}',
        sessionId: sessionId,
        priority: (m['priority'] as num?)?.toInt() ?? (i + 1),
        text: (m['text'] as String?) ?? '',
        evidenceRefs: ((m['evidenceRefs'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        whatToTryInstead: m['whatToTryInstead'] as String?,
      ));
      i++;
    }
    return recs;
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../transcription/transcription_engine.dart';

/// Single seam over the on-device model runtimes (v2, fully offline).
///
/// ALL `flutter_gemma` (LLM) and `whisper_ggml` (STT) calls live here, so if a
/// plugin's API shifts, only this file changes. The rest of the app talks to
/// the same [LLMProvider] / [TranscriptionEngine] interfaces as v1 — the
/// adapters just delegate here.
///
/// Nothing here touches the network except the one-time *model download*; no
/// transcript or analysis ever leaves the device.
class LocalModels {
  LocalModels._();
  static final LocalModels instance = LocalModels._();

  // ---- Model identities ----------------------------------------------------

  /// The on-device analysis model. Gemma 3 1B (~0.5 GB) is the size/quality
  /// sweet spot for a phone; swap the URL/type to trade up (e.g. Gemma3n E2B)
  /// or down (Qwen3 0.6B). LiteRT-LM `.litertlm` format.
  static const String gemmaModelId = 'gemma-4-e2b-it';

  /// Default download URL for the analysis model — the portable (no chipset
  /// suffix, non-web) LiteRT-LM build of Gemma 4 E2B (~2.4 GB, effective ~2B),
  /// a big quality step up from the 1B. Override the exact filename at build
  /// time with `--dart-define=GEMMA_MODEL_URL=<resolve/main/... url>` (use the
  /// `/resolve/main/` form, not `/blob/main/`) without a code change.
  static const String _defaultGemmaModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/main/gemma-4-E2B-it.litertlm';
  static const String _urlOverride = String.fromEnvironment('GEMMA_MODEL_URL');
  static String get gemmaModelUrl =>
      _urlOverride.isNotEmpty ? _urlOverride : _defaultGemmaModelUrl;

  /// flutter_gemma identifies an installed model by its **filename** (the last
  /// path segment of the download URL), so install checks must use this — not a
  /// made-up id.
  static String get gemmaModelFile => Uri.parse(gemmaModelUrl).pathSegments.last;

  /// Optional HuggingFace token, ONLY used to *download* a gated model (never
  /// for inference). Pass at build time with
  /// `--dart-define=HUGGINGFACE_TOKEN=hf_xxx`, or host an un-gated copy of the
  /// model and point [gemmaModelUrl] at it to need no token at all.
  static const String _hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

  /// The on-device transcription model. `base` (~140 MB) is a good balance;
  /// `small` (~460 MB) is more accurate but slower. whisper_ggml downloads it
  /// automatically on first use.
  WhisperModel whisperModel = WhisperModel.base;

  final WhisperController _whisper = WhisperController();

  bool _engineReady = false;
  InferenceModel? _gemma;

  // ---- Engine init (call once at startup) ----------------------------------

  Future<void> initEngine() async {
    if (_engineReady) return;
    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
    _engineReady = true;
  }

  // ---- Analysis model (Gemma) ---------------------------------------------

  Future<bool> isGemmaInstalled() async {
    try {
      return await FlutterGemma.isModelInstalled(gemmaModelFile);
    } catch (_) {
      return false;
    }
  }

  /// Downloads + installs the analysis model, reporting 0..100 progress.
  Future<void> installGemma({void Function(int percent)? onProgress}) async {
    await initEngine();
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    )
        .fromNetwork(
          gemmaModelUrl,
          token: _hfToken.isEmpty ? null : _hfToken,
        )
        .withProgress((p) => onProgress?.call(p))
        .install();
  }

  Future<void> uninstallGemma() async {
    await _closeGemma();
    try {
      await FlutterGemma.uninstallModel(gemmaModelFile);
    } catch (e) {
      debugPrint('[LOCAL] uninstallGemma failed: $e');
    }
  }

  Future<InferenceModel> _ensureGemma() async {
    await initEngine();
    return _gemma ??= await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  Future<void> _closeGemma() async {
    try {
      await _gemma?.close();
    } catch (_) {}
    _gemma = null;
  }

  /// Runs one analysis/Q&A completion fully on-device and returns the raw text
  /// (expected to be JSON — the orchestrator tolerates fences/prose around it).
  Future<String> analyze({
    required String system,
    required String user,
  }) async {
    final model = await _ensureGemma();
    // A fresh chat per call keeps each analysis independent (no history bleed).
    //
    // Budget the 4096-token context window: input (system + transcript) and
    // output must both fit. The orchestrator caps the transcript it sends
    // (see AnalysisOrchestrator._cappedForPrompt) to ~1.6k tokens, the system
    // prompt is ~0.6k, so 1536 output tokens keeps the total safely under 4096.
    // (Long meetings previously overflowed: "token ids are too long 16403 >= 4096".)
    final chat = await model.createChat(
      systemInstruction: system,
      maxOutputTokens: 1536,
    );
    await chat.addQueryChunk(Message.text(text: user, isUser: true));
    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        buffer.write(response.token);
      }
      // FunctionCallResponse is ignored — the analysis prompt registers no tools.
    }
    return buffer.toString();
  }

  // ---- Transcription model (Whisper) --------------------------------------

  /// A real ggml Whisper model is tens of MB+; anything smaller is a partial or
  /// error-page download that whisper.cpp will fail to load.
  static const int _minWhisperBytes = 10 * 1024 * 1024;

  /// True when a *complete* Whisper ggml model file is present on disk. Checks
  /// the size, not just existence — a truncated download would otherwise show
  /// as installed but fail to load at transcribe time (seen on iOS).
  Future<bool> isWhisperInstalled() async {
    try {
      final path = await _whisper.getPath(whisperModel);
      final file = File(path);
      return file.existsSync() && file.lengthSync() >= _minWhisperBytes;
    } catch (_) {
      return false;
    }
  }

  /// Ensures a complete Whisper model is on disk. whisper_ggml does NOT
  /// auto-download in this version — transcribe() just fails to load a missing
  /// (or partial) file — so we fetch it explicitly, deleting any truncated
  /// download first so it is refetched cleanly.
  Future<void> ensureWhisperReady() async {
    final path = await _whisper.getPath(whisperModel);
    final file = File(path);
    if (file.existsSync() && file.lengthSync() >= _minWhisperBytes) return;
    if (file.existsSync()) {
      debugPrint('[WHISPER] model file too small (${file.lengthSync()} bytes) '
          '— deleting and refetching');
      try {
        file.deleteSync();
      } catch (_) {}
    }
    debugPrint('[WHISPER] downloading model $whisperModel …');
    await _whisper.downloadModel(whisperModel);
    debugPrint('[WHISPER] model download complete '
        '(${file.existsSync() ? file.lengthSync() : 0} bytes)');
  }

  /// Transcribes a local audio file entirely on-device.
  Future<TranscriptionResult> transcribeFile({
    required String audioPath,
    required List<String> languages,
  }) async {
    // Make sure the model is on disk first (first run downloads ~148 MB).
    await ensureWhisperReady();
    final lang = languages.isEmpty ? 'auto' : languages.first;

    // Diagnostics (visible in `flutter run` logs AND surfaced in the on-screen
    // error) — confirm the audio file and the model file are real.
    final f = File(audioPath);
    final exists = await f.exists();
    final size = exists ? await f.length() : 0;
    String modelPath = '?';
    bool modelExists = false;
    int modelSize = 0;
    try {
      modelPath = await _whisper.getPath(whisperModel);
      final mf = File(modelPath);
      modelExists = mf.existsSync();
      modelSize = modelExists ? mf.lengthSync() : 0;
    } catch (e) {
      modelPath = 'getPath failed: $e';
    }
    debugPrint('[WHISPER] transcribe start audio(exists=$exists size=$size) '
        'model(exists=$modelExists size=$modelSize path=$modelPath) lang=$lang');

    final result = await _whisper.transcribe(
      model: whisperModel,
      audioPath: audioPath,
      lang: lang,
      withSegments: true,
      keepModelLoaded: true,
      onProgress: (p) => debugPrint('[WHISPER] progress $p'),
    );
    debugPrint('[WHISPER] transcribe done result='
        '${result == null ? 'NULL' : 'textLen=${result.transcription.text.length} '
            'segs=${result.transcription.segments?.length}'}');

    if (result == null) {
      throw Exception(
          'On-device transcription produced no result.\n'
          'model exists=$modelExists size=$modelSize\n'
          'audio exists=$exists size=$size');
    }

    final turns = <TranscriptTurn>[];
    final segments = result.transcription.segments ?? const [];
    for (final s in segments) {
      final text = s.text.trim();
      if (text.isEmpty) continue;
      turns.add(TranscriptTurn(
        startMs: s.fromTs.inMilliseconds,
        endMs: s.toTs.inMilliseconds,
        speakerTag: 'S1',
        text: text,
      ));
    }
    // Fallback: a flat transcript with no segment timings still yields a turn.
    if (turns.isEmpty) {
      final flat = result.transcription.text.trim();
      if (flat.isNotEmpty) {
        turns.add(TranscriptTurn(
            startMs: 0, endMs: 0, speakerTag: 'S1', text: flat));
      }
    }

    return TranscriptionResult(
      turns: turns,
      language: languages.isEmpty ? 'en' : languages.first,
    );
  }
}

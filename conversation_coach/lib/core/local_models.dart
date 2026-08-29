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
  static const String gemmaModelId = 'gemma3-1b-it';

  /// Default download URL for the analysis model — a portable 4-bit,
  /// 4096-context LiteRT-LM build of Gemma 3 1B. Override the exact filename at
  /// build time with `--dart-define=GEMMA_MODEL_URL=<resolve/main/... url>`
  /// (use the `/resolve/main/` form, not `/blob/main/`) without a code change.
  static const String _defaultGemmaModelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
      'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
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
      modelType: ModelType.gemmaIt,
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
    // Cap output to keep a runaway/repetition loop from ballooning the reply.
    final chat = await model.createChat(
      systemInstruction: system,
      maxOutputTokens: 1024,
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

  /// True when the Whisper ggml model file is present on disk.
  Future<bool> isWhisperInstalled() async {
    try {
      final path = await _whisper.getPath(whisperModel);
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Downloads the Whisper model if it isn't already present. whisper_ggml does
  /// NOT auto-download in this version — transcribe() just fails to load a
  /// missing file — so we fetch it explicitly. (No progress callback is exposed
  /// by the plugin, so callers show an indeterminate state.)
  Future<void> ensureWhisperReady() async {
    if (await isWhisperInstalled()) return;
    debugPrint('[WHISPER] model missing — downloading $whisperModel …');
    await _whisper.downloadModel(whisperModel);
    debugPrint('[WHISPER] model download complete');
  }

  /// Transcribes a local audio file entirely on-device.
  Future<TranscriptionResult> transcribeFile({
    required String audioPath,
    required List<String> languages,
  }) async {
    // Make sure the model is on disk first (first run downloads ~148 MB).
    await ensureWhisperReady();
    final lang = languages.isEmpty ? 'auto' : languages.first;

    // Diagnostics (visible in `flutter run` logs): confirm the audio file is
    // real and watch the model download/transcription progress.
    final f = File(audioPath);
    final exists = await f.exists();
    final size = exists ? await f.length() : 0;
    debugPrint('[WHISPER] transcribe start path=$audioPath exists=$exists '
        'size=$size bytes lang=$lang model=$whisperModel');

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
          'On-device transcription produced no result — the Whisper model may '
          'still be downloading. Wait for Wi-Fi to finish, then retry.');
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

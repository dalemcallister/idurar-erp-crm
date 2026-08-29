import 'package:flutter/foundation.dart';

import '../analysis/analysis_orchestrator.dart';
import '../analysis/qa_service.dart';
import '../data/database.dart';
import '../data/models/goal.dart';
import '../data/models/provider_config.dart';
import '../data/models/session.dart';
import '../data/repository.dart';
import '../data/secure_keystore.dart';
import '../llm/provider_registry.dart';
import '../transcription/local_whisper_transcription.dart';
import '../transcription/transcription_engine.dart';
import 'goal_templates.dart';
import 'local_models.dart';
import 'pricing.dart';

/// Settings keys persisted in the encrypted `app_settings` table.
class SettingsKeys {
  /// The provider the user *wants* to use — durably remembered so a temporary
  /// offline fallback never loses it.
  static const preferredProvider = 'preferredProviderConfigId';
  static const language = 'language';
  static const transcriptionEngine = 'transcriptionEngine'; // cloud|demo
  static const retentionAudioDays = 'retentionAudioDays';
  static const asrEndpoint = 'asrEndpoint';
  static const asrModel = 'asrModel';

  /// Prepaid spend budget (a "deposit" the cost meter draws down). USD.
  static const budgetDeposit = 'budgetDepositUsd';
  static const budgetSpent = 'budgetSpentUsd';

  /// Keystore handle for the speech-to-text (ASR) provider key — separate from
  /// the analysis provider's key, since transcription uses a different service.
  static const asrKeyRef = 'asr_api_key';
}

/// Central application state and service wiring (a lightweight service locator
/// exposed via Provider). Owns initialization, template seeding, settings, and
/// the provider-selection logic — including remembering the preferred provider
/// so the offline demo fallback can always be reverted.
class AppState extends ChangeNotifier {
  final SecureKeystore keystore;
  final AppDatabase database;
  late final Repository repo;
  late final ProviderRegistry providerRegistry;
  late final AnalysisOrchestrator orchestrator;
  late final QAService qaService;

  AppState({SecureKeystore? keystore, AppDatabase? database})
      : keystore = keystore ?? SecureKeystore(),
        database = database ?? AppDatabase(keystore ?? SecureKeystore());

  bool _ready = false;
  bool get ready => _ready;

  List<ProviderConfig> providerConfigs = [];
  List<Goal> goals = [];

  String language = 'en';
  String transcriptionEngineKind = 'demo'; // 'cloud' | 'demo'
  int retentionAudioDays = 30;

  /// Speech-to-text (Whisper-compatible) provider used when the cloud engine
  /// is selected. Defaults to OpenAI Whisper.
  String asrEndpoint = 'https://api.openai.com/v1';
  String asrModel = 'whisper-1';

  /// Prepaid spend budget (F-MOD-06 extension). [budgetDeposit] is the total
  /// topped up; [budgetSpent] is the running estimated spend drawn against it.
  double budgetDeposit = 0;
  double budgetSpent = 0;

  bool get budgetEnabled => budgetDeposit > 0;
  double get budgetRemaining =>
      (budgetDeposit - budgetSpent).clamp(0.0, double.infinity);
  bool get budgetExhausted => budgetEnabled && budgetRemaining <= 0;
  bool get budgetLow =>
      budgetEnabled &&
      budgetRemaining > 0 &&
      budgetRemaining < budgetDeposit * 0.15;

  /// Id of the provider the user prefers. v2 is on-device only, so this is the
  /// local Gemma provider.
  String preferredProviderId = ProviderConfig.localGemma().id;

  /// On-device analysis-model download state (v2). Null when idle; 0..100 while
  /// downloading.
  int? gemmaDownloadPercent;
  bool gemmaInstalled = false;

  /// Last model-download error, surfaced in Settings so failures aren't silent.
  String? gemmaError;

  /// Per-session analysis-pipeline error, surfaced on the failed session screen
  /// so transcription/analysis failures are diagnosable on-device.
  final Map<String, String> analysisErrors = {};

  /// On-device transcription-model (Whisper) state. No download progress is
  /// available from the plugin, so [whisperDownloading] drives a spinner.
  bool whisperInstalled = false;
  bool whisperDownloading = false;
  String? whisperError;

  Future<void> init() async {
    await database.open();
    repo = Repository(database);
    providerRegistry = ProviderRegistry(keystore);
    orchestrator =
        AnalysisOrchestrator(repo: repo, providers: providerRegistry);
    qaService = QAService(repo: repo, providers: providerRegistry);

    await _seedIfNeeded();
    await _loadSettings();
    await refresh();

    // v2 is on-device only: force the local provider even if an older install
    // had a cloud provider selected.
    if (preferredProvider.provider != ProviderKind.local &&
        preferredProvider.provider != ProviderKind.mock) {
      await selectProvider(ProviderConfig.localGemma().id);
    }
    gemmaInstalled = await LocalModels.instance.isGemmaInstalled();
    whisperInstalled = await LocalModels.instance.isWhisperInstalled();

    _ready = true;
    notifyListeners();
  }

  Future<void> _seedIfNeeded() async {
    // Goal/rubric templates — upsert every launch (stable ids), so newly added
    // templates appear on existing installs too. Custom user goals are untouched.
    for (final r in GoalTemplates.rubrics()) {
      await repo.upsertRubric(r);
    }
    for (final g in GoalTemplates.goals()) {
      await repo.upsertGoal(g);
    }

    // v2 provider configs: the on-device Gemma provider (default) + the offline
    // demo fallback. Upserted every launch (stable ids) so the on-device
    // provider always exists, including on installs upgraded from v1.
    await repo.upsertProviderConfig(ProviderConfig.localGemma());
    await repo.upsertProviderConfig(ProviderConfig.mock());
    final configs = await repo.providerConfigs();
    if (configs.isEmpty ||
        await repo.getSetting(SettingsKeys.preferredProvider) == null) {
      await repo.setSetting(
          SettingsKeys.preferredProvider, ProviderConfig.localGemma().id);
    }
  }

  Future<void> _loadSettings() async {
    preferredProviderId =
        await repo.getSetting(SettingsKeys.preferredProvider) ??
            ProviderConfig.localGemma().id;
    language = await repo.getSetting(SettingsKeys.language) ?? 'en';
    transcriptionEngineKind =
        await repo.getSetting(SettingsKeys.transcriptionEngine) ?? 'demo';
    retentionAudioDays = int.tryParse(
            await repo.getSetting(SettingsKeys.retentionAudioDays) ?? '30') ??
        30;
    asrEndpoint = await repo.getSetting(SettingsKeys.asrEndpoint) ??
        'https://api.openai.com/v1';
    asrModel = await repo.getSetting(SettingsKeys.asrModel) ?? 'whisper-1';
    budgetDeposit =
        double.tryParse(await repo.getSetting(SettingsKeys.budgetDeposit) ?? '') ??
            0;
    budgetSpent =
        double.tryParse(await repo.getSetting(SettingsKeys.budgetSpent) ?? '') ??
            0;
  }

  Future<void> refresh() async {
    providerConfigs = await repo.providerConfigs();
    goals = await repo.goals();
    notifyListeners();
  }

  // ---- Provider selection & fallback memory --------------------------------

  /// The provider the user prefers (what analysis will *try* to use).
  ProviderConfig get preferredProvider => providerConfigs.firstWhere(
        (c) => c.id == preferredProviderId,
        orElse: () => providerConfigs.isEmpty
            ? ProviderConfig.defaultClaude()
            : providerConfigs.first,
      );

  /// True when analysis will fall back to the offline demo. In v2 that means
  /// the on-device analysis model hasn't been downloaded yet (until then the
  /// built-in demo analysis is used).
  Future<bool> isFallbackActive() async {
    final p = preferredProvider;
    if (p.provider == ProviderKind.mock) return false;
    if (p.provider == ProviderKind.local) {
      return !(await LocalModels.instance.isGemmaInstalled());
    }
    if (p.apiKeyRef == null) return true;
    return !(await keystore.has(p.apiKeyRef!));
  }

  /// Selects the active provider and remembers the choice.
  Future<void> selectProvider(String configId) async {
    preferredProviderId = configId;
    await repo.setSetting(SettingsKeys.preferredProvider, configId);
    notifyListeners();
  }

  /// One-tap revert to the Claude default — the configuration is always present
  /// because the demo fallback never removed it.
  Future<void> revertToClaudeDefault() async {
    final claude = providerConfigs.firstWhere(
      (c) => c.provider == ProviderKind.anthropic,
      orElse: () => ProviderConfig.defaultClaude(),
    );
    // Ensure it exists (defensive — it is seeded on first run).
    await repo.upsertProviderConfig(claude);
    await selectProvider(claude.id);
    await refresh();
  }

  /// Stores a provider's API key in the OS keystore (never in the database).
  /// After this, [isFallbackActive] returns false and the preferred provider is
  /// live again.
  Future<void> setApiKey(ProviderConfig config, String key) async {
    final ref = config.apiKeyRef ?? '${config.id}_api_key';
    await keystore.write(ref, key);
    if (config.apiKeyRef != ref) {
      await repo.upsertProviderConfig(config.copyWith(apiKeyRef: ref));
      await refresh();
    }
    notifyListeners();
  }

  Future<void> clearApiKey(ProviderConfig config) async {
    if (config.apiKeyRef != null) {
      await keystore.delete(config.apiKeyRef!);
    }
    notifyListeners();
  }

  Future<bool> hasApiKey(ProviderConfig config) async =>
      config.apiKeyRef != null && await keystore.has(config.apiKeyRef!);

  Future<void> upsertProvider(ProviderConfig config) async {
    await repo.upsertProviderConfig(config);
    await refresh();
  }

  // ---- Other settings ------------------------------------------------------

  Future<void> setLanguage(String lang) async {
    language = lang;
    await repo.setSetting(SettingsKeys.language, lang);
    notifyListeners();
  }

  Future<void> setTranscriptionEngine(String kind) async {
    transcriptionEngineKind = kind;
    await repo.setSetting(SettingsKeys.transcriptionEngine, kind);
    notifyListeners();
  }

  Future<void> setRetentionAudioDays(int days) async {
    retentionAudioDays = days;
    await repo.setSetting(SettingsKeys.retentionAudioDays, days.toString());
    await repo.applyAudioRetention(days);
    notifyListeners();
  }

  // ---- Prepaid spend budget ------------------------------------------------

  /// Top up the deposit (a manual prepaid amount — no payment processor; in the
  /// bring-your-own-key model the user pays their providers directly).
  Future<void> addDeposit(double usd) async {
    if (usd <= 0) return;
    budgetDeposit += usd;
    await repo.setSetting(
        SettingsKeys.budgetDeposit, budgetDeposit.toString());
    notifyListeners();
  }

  /// Draw down the budget by an estimated session cost.
  Future<void> recordSpend(double usd) async {
    if (usd <= 0 || !budgetEnabled) return;
    budgetSpent += usd;
    await repo.setSetting(SettingsKeys.budgetSpent, budgetSpent.toString());
    notifyListeners();
  }

  /// Clear the budget entirely (deposit and spend back to zero).
  Future<void> resetBudget() async {
    budgetDeposit = 0;
    budgetSpent = 0;
    await repo.setSetting(SettingsKeys.budgetDeposit, '0');
    await repo.setSetting(SettingsKeys.budgetSpent, '0');
    notifyListeners();
  }

  // ---- ASR (speech-to-text) provider --------------------------------------

  Future<void> setAsrEndpoint(String url) async {
    asrEndpoint = url;
    await repo.setSetting(SettingsKeys.asrEndpoint, url);
    notifyListeners();
  }

  Future<void> setAsrModel(String model) async {
    asrModel = model;
    await repo.setSetting(SettingsKeys.asrModel, model);
    notifyListeners();
  }

  Future<void> setAsrKey(String key) async {
    await keystore.write(SettingsKeys.asrKeyRef, key);
    notifyListeners();
  }

  Future<void> clearAsrKey() async {
    await keystore.delete(SettingsKeys.asrKeyRef);
    notifyListeners();
  }

  Future<bool> hasAsrKey() => keystore.has(SettingsKeys.asrKeyRef);

  /// Builds the transcription engine (v2: always on-device Whisper). Audio
  /// never leaves the device.
  Future<TranscriptionEngine> transcriptionEngine() async {
    return LocalWhisperEngine();
  }

  // ---- On-device models (v2) ----------------------------------------------

  /// Downloads + installs the on-device analysis model, streaming progress into
  /// [gemmaDownloadPercent].
  Future<void> installGemma() async {
    gemmaError = null;
    gemmaDownloadPercent = 0;
    notifyListeners();
    try {
      await LocalModels.instance.installGemma(onProgress: (p) {
        gemmaDownloadPercent = p;
        notifyListeners();
      });
      gemmaInstalled = true;
    } catch (e, st) {
      gemmaError = e.toString();
      debugPrint('[LOCAL] gemma install failed: $e\n$st');
    } finally {
      gemmaDownloadPercent = null;
      gemmaInstalled = await LocalModels.instance.isGemmaInstalled();
      notifyListeners();
    }
  }

  /// Downloads the on-device transcription model (Whisper). No progress is
  /// reported by the plugin, so this just toggles [whisperDownloading].
  Future<void> installWhisper() async {
    whisperError = null;
    whisperDownloading = true;
    notifyListeners();
    try {
      await LocalModels.instance.ensureWhisperReady();
      whisperInstalled = true;
    } catch (e, st) {
      whisperError = e.toString();
      debugPrint('[LOCAL] whisper install failed: $e\n$st');
    } finally {
      whisperDownloading = false;
      whisperInstalled = await LocalModels.instance.isWhisperInstalled();
      notifyListeners();
    }
  }

  /// Removes the on-device analysis model to reclaim storage.
  Future<void> removeGemma() async {
    await LocalModels.instance.uninstallGemma();
    gemmaInstalled = false;
    notifyListeners();
  }

  Future<bool> refreshGemmaInstalled() async {
    gemmaInstalled = await LocalModels.instance.isGemmaInstalled();
    notifyListeners();
    return gemmaInstalled;
  }

  // ---- Analysis pipeline ---------------------------------------------------

  /// Runs transcription + analysis for a recorded session against its goal and
  /// rubric, drawing the estimated cost down from the prepaid budget. Marks the
  /// session failed on any error. Shared by live recording and the retry action
  /// so a transient failure (e.g. a flaky network) can be re-run on the audio
  /// already on disk — no re-recording needed.
  Future<void> runAnalysisPipeline(Session session, String audioPath) async {
    analysisErrors.remove(session.id);
    try {
      final goal = await repo.goal(session.goalId);
      final rubric = goal == null ? null : await repo.rubric(goal.rubricId);
      if (goal == null || rubric == null) {
        debugPrint('[PIPELINE] missing goal/rubric for ${session.goalId} '
            '-> marking failed');
        analysisErrors[session.id] =
            'Missing goal/rubric for this session.';
        await repo.updateSessionStatus(session.id, SessionStatus.failed);
        notifyListeners();
        return;
      }
      final engine = await transcriptionEngine();
      final analysis = await orchestrator.run(
        session: session,
        goal: goal,
        rubric: rubric,
        transcriptionEngine: engine,
        providerConfig: preferredProvider,
        audioPath: audioPath,
      );
      // Draw the estimated cost down from the prepaid budget (F-MOD-06).
      final cost = Pricing.estimateCost(
          analysis.modelUsed, analysis.inputTokens, analysis.outputTokens);
      if (cost != null) await recordSpend(cost);
    } catch (e, st) {
      debugPrint('[PIPELINE] FAILED for ${session.id}: $e\n$st');
      analysisErrors[session.id] = e.toString();
      await repo.updateSessionStatus(session.id, SessionStatus.failed);
      notifyListeners();
    }
  }

  // ---- Destructive: wipe everything (F-DAT-02) -----------------------------

  Future<void> wipeEverything() async {
    await database.deleteFile();
    await keystore.wipeAll();
    // Re-open a fresh, empty, encrypted database and re-seed templates.
    await database.open();
    repo = Repository(database);
    await _seedIfNeeded();
    await _loadSettings();
    await refresh();
    notifyListeners();
  }

  Future<List<Session>> sessions({String query = ''}) =>
      repo.sessions(query: query);
}

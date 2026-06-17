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
import '../transcription/cloud_transcription.dart';
import '../transcription/mock_transcription.dart';
import '../transcription/transcription_engine.dart';
import 'goal_templates.dart';

/// Settings keys persisted in the encrypted `app_settings` table.
class SettingsKeys {
  /// The provider the user *wants* to use — durably remembered so a temporary
  /// offline fallback never loses it.
  static const preferredProvider = 'preferredProviderConfigId';
  static const language = 'language';
  static const transcriptionEngine = 'transcriptionEngine'; // cloud|demo
  static const retentionAudioDays = 'retentionAudioDays';
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

  /// Id of the provider the user prefers (remembered across fallbacks).
  String preferredProviderId = ProviderConfig.defaultClaude().id;

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

    _ready = true;
    notifyListeners();
  }

  Future<void> _seedIfNeeded() async {
    // Goal/rubric templates.
    final existingGoals = await repo.goals();
    if (existingGoals.isEmpty) {
      for (final r in GoalTemplates.rubrics()) {
        await repo.upsertRubric(r);
      }
      for (final g in GoalTemplates.goals()) {
        await repo.upsertGoal(g);
      }
    }

    // Default provider configs: Claude (default, F-MOD-01) + the offline demo.
    // These are persisted once and then never silently overwritten, so the
    // user's real configuration survives any temporary fallback.
    final configs = await repo.providerConfigs();
    if (configs.isEmpty) {
      await repo.upsertProviderConfig(ProviderConfig.defaultClaude());
      await repo.upsertProviderConfig(ProviderConfig.mock());
      await repo.setSetting(
          SettingsKeys.preferredProvider, ProviderConfig.defaultClaude().id);
    }
  }

  Future<void> _loadSettings() async {
    preferredProviderId =
        await repo.getSetting(SettingsKeys.preferredProvider) ??
            ProviderConfig.defaultClaude().id;
    language = await repo.getSetting(SettingsKeys.language) ?? 'en';
    transcriptionEngineKind =
        await repo.getSetting(SettingsKeys.transcriptionEngine) ?? 'demo';
    retentionAudioDays = int.tryParse(
            await repo.getSetting(SettingsKeys.retentionAudioDays) ?? '30') ??
        30;
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

  /// True when the preferred provider needs a key but none is stored — meaning
  /// analysis will transparently fall back to the offline demo provider. The
  /// preferred config is untouched and can be reverted to the moment a key is
  /// added (e.g. back at your desktop).
  Future<bool> isFallbackActive() async {
    final p = preferredProvider;
    if (p.provider == ProviderKind.mock) return false;
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

  /// Builds the transcription engine for the current setting. The cloud engine
  /// only sends audio when the user has opted in and configured a provider.
  Future<TranscriptionEngine> transcriptionEngine() async {
    if (transcriptionEngineKind == 'cloud') {
      final p = preferredProvider;
      final key = p.apiKeyRef == null ? null : await keystore.read(p.apiKeyRef!);
      if ((key ?? '').isNotEmpty) {
        return CloudTranscriptionEngine(
          endpointUrl: p.endpointUrl.isEmpty
              ? 'https://api.openai.com/v1'
              : p.endpointUrl,
          apiKey: key,
        );
      }
    }
    return MockTranscriptionEngine();
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

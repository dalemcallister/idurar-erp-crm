# Conversation Coach (ClariConvo)

A goal-aligned communication-coaching mobile app. You record a real
conversation through a high-quality USB-C microphone, set a goal for it, and
afterwards receive a structured, evidence-backed read on what was said, what was
meant, how it landed, and how to do better — and can then ask questions about
that specific conversation in plain language.

Built in **Flutter** from the three companion specifications (Design,
Functional, Technical). This is the **Phase 1 — MVP** scope: record → cloud or
on-device transcription → goal-scored analysis via **Claude** → evidence-cited
recommendations → per-session "ask the conversation" Q&A → encrypted local
storage → consent step → export and delete.

> The analysis model is **user-selectable**, and **Claude is the default**. The
> app is **bring-your-own-key**: you add your Anthropic key at runtime, and if
> no key is set the app transparently falls back to a built-in **offline demo
> provider** so the whole loop still runs end-to-end.

---

## Running it

This repository ships the application source (`lib/`), tests, and the
platform permission manifests. Regenerate the platform scaffolding, then run:

```bash
cd conversation_coach

# 1. Generate the iOS/Android/desktop project scaffolding around this code.
#    (Keep the provided AndroidManifest.xml / ios Info.plist — they hold the
#    microphone, USB-host and background-audio permissions; re-apply them if
#    `flutter create` overwrites them.)
flutter create .

flutter pub get

# 2. Run the tests (pure-Dart analysis logic).
flutter test

# 3. Launch on a device/emulator. The DJI Mic over USB-C is the validated
#    reference input; the built-in mic works too.
flutter run
```

On first launch the app seeds goal templates and two provider configs (Claude
default + offline demo), opens an encrypted SQLCipher database, and lands on the
**Record** tab.

### Using Claude

Settings → **Model & provider** → on the *Anthropic (Claude)* row tap **Add
key**, paste your Anthropic API key, then **Test**. The key is stored only in
the OS keystore (Keychain / Android Keystore), never in the database or in
plaintext. The default model is `claude-opus-4-8`.

Without a key the app uses the **offline demo** provider, which synthesises a
realistic, schema-correct analysis from the transcript so you can exercise every
screen.

---

## Your configuration is remembered and revertible

Because this environment has no Anthropic key, analysis runs on the offline demo
provider. That fallback is **non-destructive**:

- Your **preferred provider** (Claude by default) and any providers/keys you add
  are stored durably in the encrypted DB / keystore and in the
  `app_settings.preferredProviderConfigId` setting. The fallback **never
  overwrites or deletes** them — it only resolves a different adapter *at call
  time* when no key is present (`ProviderRegistry.resolveForAnalysis`).
- When you get to your desktop and add an Anthropic key, the preferred provider
  goes live again automatically — nothing to reconfigure.
- Settings shows a banner whenever the demo fallback is active, plus a one-tap
  **Restore Claude default** button (`AppState.revertToClaudeDefault`).

---

## Architecture (maps to the Technical Specification)

```
Flutter client
  UI  |  AudioCapture  |  Encrypted store (SQLCipher)  |  AnalysisOrchestrator
        |                  |                               |
        v                  v                               v
  TranscriptionEngine   FeatureExtractor              Model Abstraction Layer
  (cloud OR demo)       (dynamics + prosody)          +-----------+-----------+--------+
                                                      | Anthropic | OpenAI-   | Ollama |
                                                      | (Claude)  | compatible| (local)|
                                                      +-----------+-----------+--------+
                                                      + offline demo (key-less fallback)
```

| Spec area | Where it lives |
|---|---|
| Model Abstraction Layer (§5) | `lib/llm/llm_provider.dart` + adapters (`anthropic_adapter`, `openai_compatible_adapter`, `mock_adapter`) + `provider_registry.dart` |
| Versioned prompt registry (§5) | `lib/llm/prompt_registry.dart` |
| Analysis pipeline stages (§6.1) | `lib/analysis/analysis_orchestrator.dart` |
| Transcription engines (§6.2) | `lib/transcription/*` (cloud + offline demo; on-device Whisper is Phase 3) |
| Emotion & dynamics (§6.3) | `lib/audio/feature_extractor.dart` |
| Q&A grounding / retrieval (§6.4) | `lib/analysis/qa_service.dart` |
| Logical data model (§7) | `lib/data/models/*` + `lib/data/database.dart` |
| Security & privacy (§8) | `lib/data/secure_keystore.dart` (keystore), SQLCipher DB, retention + wipe in `repository.dart` |
| Audio capture, USB-C UAC (§4) | `lib/audio/audio_capture.dart` + platform manifests |

### Functional requirements coverage (Phase 1)

Capture (F-CAP-01..06/09), consent (F-CON-01/02/04/05), transcription
(F-TRA-01/02/05), goals & rubrics (F-GOAL-01/02), analysis
(F-ANA-01..06), recommendations (F-REC-01/02), Q&A (F-QA-01/02/04), progress
(F-PRO-01), model/provider (F-MOD-01/02/03/04/07), and data (F-DAT-01/02/03)
are implemented. Items marked SHOULD/MAY or Phase 2/3 (diarization from mixed
audio, acoustic prosody from the raw waveform, PII redaction, cross-session
Q&A, Ollama, on-device Whisper, custom-rubric editing) are stubbed behind the
same interfaces so they slot in without a rewrite.

---

## Notes & limitations

- **Offline demo transcription** produces a representative sample conversation
  scaled to the real recording length, so the analysis loop runs with no audio
  leaving the device. Wire a cloud ASR provider (Settings → Transcription →
  Cloud) for real transcription.
- Acoustic/prosodic features are currently derived from timing and text; the
  hooks to compute them from the full-quality USB-C waveform are in
  `FeatureExtractor` (Phase 2).
- The SQLCipher database key is generated with `Random.secure()` (a
  cryptographically secure RNG) on first run and then held in the OS keystore.

# Conversation Coach — agent orientation

Conversation Coach (ClariConvo) is a Flutter iOS/Android app: record a
conversation, transcribe + analyse it against a goal-specific weighted rubric,
and get evidence-backed coaching plus a per-session Q&A. It is one part of a
larger product for building communication skills.

**Read `PROJECT.md` first** — it is the living project tracker (vision, current
status, roadmap, decisions). Build/platform details: `V2_SETUP.md`. Branding:
`BRANDING.md`. Distribution: `DISTRIBUTION.md` / `TESTFLIGHT.md`.

## Branches
- `v2-on-device` — v2, fully on-device (current work). PR #2.
- `v1-cloud` — v1 (cloud, bring-your-own-key). Frozen. PR #1.
- `master` — upstream IDURAR ERP/CRM; unrelated to this app (the app lives only
  in the branches above).

## v2 = fully on-device (no API keys, nothing leaves the phone)
- Analysis: **Gemma 4 E2B** via `flutter_gemma` (LiteRT-LM).
- Transcription: **Whisper base** via `whisper_ggml` (whisper.cpp).
- ALL native model calls are isolated in **`lib/core/local_models.dart`** —
  change models/plugins there and nowhere else.

## Non-obvious gotchas (don't relearn these the hard way)
- **iOS Podfile MUST use dynamic `use_frameworks!`** — `:linkage => :static`
  dead-strips whisper_ggml's FFI symbol (`dlsym(RTLD_DEFAULT,'request')`) and
  transcription silently returns null.
- **Android:** NDK `29.0.13113456`, `compileSdk 36`, `arm64-v8a` only; the root
  `android/build.gradle.kts` forces these onto plugin modules. (Local files —
  see `V2_SETUP.md`.)
- **Record at 16 kHz mono** — whisper needs it; other rates transcribe empty.
- **Small-model JSON is unreliable** → `analysis_orchestrator._parseJson`
  repairs common slips and falls back to field extraction. Keep it resilient.
- **DB writes:** sessions use UPDATE-in-place, never `INSERT OR REPLACE`
  (cascade deletes wiped analyses during v1).

## Build
- Android: `flutter build apk --release --dart-define=HUGGINGFACE_TOKEN=hf_...`
- iOS: `flutter build ipa --dart-define=HUGGINGFACE_TOKEN=hf_...` → Transporter → TestFlight
- The HF token only downloads the (gated) Gemma model. **Swap to an un-gated
  model before wide distribution** so no token ships in the build.
- Any Dart or Podfile/Gradle change → new build + re-upload (TestFlight/APK);
  stores don't push code changes on their own.

## Conventions
- Commit trailers: `Co-Authored-By:` + `Claude-Session:` (match repo history).
- Never put a model identifier in commits/PRs/code.
- **Privacy invariant:** conversation audio/transcripts stay on-device. Only
  derived achievements (skills, badges, scores) are ever shareable, and only on
  explicit user action.

## Keeping track
Update `PROJECT.md` (status + decisions log) whenever meaningful work lands.
Chat context is ephemeral; these committed docs are the project's memory.

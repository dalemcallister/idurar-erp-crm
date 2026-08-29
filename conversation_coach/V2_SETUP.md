# v2 — Fully on-device (no keys, nothing leaves the phone)

v2 replaces the cloud path entirely:

- **Analysis** runs on a local **Gemma 3 1B** model via `flutter_gemma` (LiteRT-LM).
- **Transcription** runs on a local **Whisper** model via `whisper_ggml` (whisper.cpp).

No API keys, no accounts, and no audio/transcript ever leaves the device. v1
(cloud, bring-your-own-key) is preserved on the **`v1-cloud`** branch.

All plugin calls are isolated in `lib/core/local_models.dart` — if a plugin's
API differs from what was coded against, that's the only file to adjust.

---

## 1. Get the packages

```bash
flutter pub get
```

The dependencies are declared as `any` in `pubspec.yaml` so the resolver picks
current versions. Once `pub get` succeeds, **pin them** to the resolved versions
(copy the versions from `pubspec.lock` back into `pubspec.yaml`) for reproducible
builds.

## 2. Platform build config (local — not in the repo)

The tracked files (`Info.plist`, `AndroidManifest.xml`, `pubspec.yaml`) are
already updated. The generated project files below are **not** in the repo, so
apply these on your machine.

### iOS (`ios/Podfile`)
- Raise the platform and use static frameworks (required by `flutter_gemma`):
  ```ruby
  platform :ios, '15.6'          # whisper_ggml needs 15.6; gemma needs 15+
  use_frameworks! :linkage => :static
  ```
- Set the deployment target to **15.6** for the Runner target in Xcode too.
- For large models, add to `ios/Runner/Runner.entitlements`:
  ```xml
  <key>com.apple.developer.kernel.extended-virtual-addressing</key>
  <true/>
  ```
- Then: `cd ios && pod install && cd ..`

### Android (`android/app/build.gradle.kts`)
- `flutter_gemma`'s LiteRT-LM `.litertlm` runtime is **arm64 only** — restrict ABIs:
  ```kotlin
  android {
    defaultConfig {
      ndk { abiFilters += listOf("arm64-v8a") }
    }
  }
  ```
- `minSdk` 24 (already set) is fine (gemma needs 21+, whisper 21+).
- The `libOpenCL.so` GPU hint is already in the tracked `AndroidManifest.xml`.

> Note: arm64-only means the app won't run on the **Android emulator on an Intel
> Mac** or on 32-bit devices. Test on a real arm64 phone (Apple Silicon Macs'
> emulators are arm64 and are fine).

## 3. Models

- **Analysis model (Gemma 3 1B, ~0.5 GB):** downloaded on demand from
  **Settings → On-device models → Download analysis model** (progress shown).
  - The default URL (`litert-community/Gemma3-1B-IT`) is a **gated** HuggingFace
    repo. To download it you either:
    - pass a free HuggingFace token at build time:
      `flutter run --dart-define=HUGGINGFACE_TOKEN=hf_xxxxx`
      (and likewise for `flutter build`), **or**
    - host an un-gated copy of `model.litertlm` and change `gemmaModelUrl` in
      `lib/core/local_models.dart` to point at it (then no token is needed).
  - The token is used **only** to download the file — never for inference.
- **Transcription model (Whisper base, ~140 MB):** `whisper_ggml` downloads it
  automatically the first time you record. The first recording will take longer
  while it fetches.

## 4. Run

```bash
flutter run --dart-define=HUGGINGFACE_TOKEN=hf_xxxxx   # on a real arm64 device
```

Then in the app: **Settings → On-device models → Download analysis model**,
record a conversation, and the whole pipeline (transcribe → analyse → Ask) runs
locally.

---

## Known limitations / iteration notes

These are expected trade-offs of going fully on-device; we'll tune them on-device:

- **Analysis quality:** a 1B model is much weaker than Claude at strict JSON,
  rubric scoring, and evidence-by-segment-id citation. The orchestrator already
  tolerates fences/loose JSON, but expect rougher analyses. Options to improve:
  step up to a bigger model (Gemma3n E2B ~3.1 GB) in `local_models.dart`, or
  simplify the analysis prompt/schema for small models.
- **Context window:** the local model runs with `maxTokens: 2048`. A long
  meeting's transcript may exceed that. If analyses truncate or fail on long
  sessions, we'll add transcript chunking/summarisation before the analysis
  call (similar to how v1 chunked audio for Whisper).
- **Performance:** on-device analysis takes noticeably longer than the cloud and
  needs a recent, higher-RAM phone; older devices may be slow or run out of
  memory. The GPU backend (`PreferredBackend.gpu`) helps where available.
- **Whisper audio format:** whisper wants 16 kHz mono; `whisper_ggml` converts
  automatically, but if transcripts look wrong we may resample/downmix the WAV
  before handing it over.
- **App size / device support:** arm64-only; models are downloaded (not bundled)
  to keep the binary small.

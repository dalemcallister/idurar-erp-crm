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

### iOS (`ios/Podfile`) — confirmed working config
```ruby
platform :ios, '15.6'   # whisper_ggml needs 15.6; gemma needs 15+
...
target 'Runner' do
  use_frameworks!        # DYNAMIC — see note below. Do NOT use :linkage => :static.
  ...
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.6'
    end
  end
end
```

> **Critical — use DYNAMIC frameworks, not static.** flutter_gemma's docs suggest
> `use_frameworks! :linkage => :static`, but static linking dead-strips
> `whisper_ggml`'s FFI entry symbol (looked up at runtime via
> `dlsym(RTLD_DEFAULT, 'request')`), so transcription returns null on-device
> with `Failed to lookup symbol 'request'`. Plain `use_frameworks!` (dynamic)
> exports the symbol AND still links Gemma's LiteRT-LM libs fine — both work.

- Set the Runner target's **Minimum Deployment** to iOS **15.6** in Xcode.
- Then: `cd ios && pod install && cd ..`
- The `extended-virtual-addressing` entitlement was **not** needed for Gemma 4
  E2B on a 16 GB device; add it only if a larger model fails to load for memory.

### Android — confirmed working config

First install **Android SDK Command-line Tools** (Android Studio → SDK Manager →
SDK Tools) and accept licenses: `flutter doctor --android-licenses`. The build
needs **NDK 29.0.13113456** and **compileSdk 36** (pulled in by whisper_ggml /
ffmpeg_kit); Gradle downloads them once licenses are accepted.

**`android/app/build.gradle.kts`** — in `android { }`:
```kotlin
android {
    compileSdk = 36
    ndkVersion = "29.0.13113456"
    defaultConfig {
        minSdk = 24
        // flutter_gemma's LiteRT-LM runtime is arm64-only.
        ndk { abiFilters += listOf("arm64-v8a") }
        // ...existing applicationId/targetSdk/version lines...
    }
}
```

**`android/build.gradle.kts`** (root) — plugin modules don't inherit the app's
compileSdk/NDK, so force them project-wide. Add this block **above** the
existing `subprojects { project.evaluationDependsOn(":app") }`:
```kotlin
subprojects {
    val configureAndroid = {
        if (project.hasProperty("android")) {
            val androidExt =
                project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            androidExt.compileSdkVersion(36)
            androidExt.ndkVersion = "29.0.13113456"
        }
    }
    if (state.executed) configureAndroid() else afterEvaluate { configureAndroid() }
}
```

- arm64-only means no Intel-Mac emulator / 32-bit devices — test on a real
  arm64 phone (Apple-Silicon Mac emulators are arm64 and fine).
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
- **Context window (handled):** the local model runs with a 4096-token window.
  Long meetings overflowed it (a ~9-min transcript ≈ 16k tokens →
  `token ids are too long 16403 >= 4096`). `AnalysisOrchestrator._cappedForPrompt`
  now evenly **samples** segments across the whole conversation to ~6k chars
  (≈ 1.6k tokens) before the analysis call, and `maxOutputTokens` is 1536, so
  input+output fit 4096. Full segments still drive dynamics/emotion/Q&A. The
  planned upgrade is map-reduce **summarisation** (better quality than sampling)
  — see PROJECT.md decisions log / roadmap #5.
- **Performance:** on-device analysis takes noticeably longer than the cloud and
  needs a recent, higher-RAM phone; older devices may be slow or run out of
  memory. The GPU backend (`PreferredBackend.gpu`) helps where available.
- **Whisper audio format:** whisper wants 16 kHz mono; `whisper_ggml` converts
  automatically, but if transcripts look wrong we may resample/downmix the WAV
  before handing it over.
- **App size / device support:** arm64-only; models are downloaded (not bundled)
  to keep the binary small.

# Distribution guide — Conversation Coach

How to get the app onto your partners' phones. Two tracks: **Android** (fast,
no account needed to start) and **iOS / TestFlight** (needs an Apple Developer
Program account). Distribution model: **bring-your-own-key** — each person adds
their own Anthropic + OpenAI keys on first run (no shared backend).

---

## 0. App identity (do once, before distributing)

The defaults from `flutter create .` use `com.example.conversationCoach`. Pick a
real reverse-domain id before sharing builds:

- **iOS** — open `ios/Runner.xcworkspace` in Xcode → *Runner* target → *Signing
  & Capabilities* → set **Team** and a unique **Bundle Identifier**
  (e.g. `com.yourco.conversationcoach`).
- **Android** — in `android/app/build.gradle.kts` set
  `applicationId = "com.yourco.conversationcoach"` and
  `minSdk = 24` (some plugins — `record`, `sqflite_sqlcipher` — need ≥ 23).
- **App name / icon** — display name is "Conversation Coach" (set in the tracked
  `AndroidManifest.xml` and `ios/Runner/Info.plist`). Add an icon with the
  `flutter_launcher_icons` package when you're ready.

---

## 1. What each partner does on first run (BYO key)

1. Install the app (Android APK or TestFlight — below).
2. Open **Settings → Model & provider → Anthropic (Claude) → Add key**, paste an
   **Anthropic API key**, tap **Test**.
3. **Settings → Transcription engine → Cloud — Whisper → Add key**, paste an
   **OpenAI API key** (used only for speech-to-text).
4. Done — record a session. Keys are stored in the device keystore, never synced.

> Each partner needs their own keys (console.anthropic.com and
> platform.openai.com). Their usage bills to their own accounts. Without keys
> the app still runs on the built-in offline demo (sample transcript + heuristic
> analysis), so they can try the UI before adding keys.

---

## 2. Android

### Run on an emulator / your own device
```bash
cd conversation_coach
flutter pub get
flutter run            # pick an emulator or a USB-connected Android phone
```

### Build a shareable APK
For a quick pilot you can share a debug-signed APK (installs on any device with
"install unknown apps" enabled):
```bash
flutter build apk --debug
# output: build/app/outputs/flutter-apk/app-debug.apk  — send this file
```

For a proper release build, create an upload keystore once:
```bash
keytool -genkey -v -keystore ~/conversation-coach-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Add `android/key.properties` (git-ignored):
```
storePassword=<...>
keyPassword=<...>
keyAlias=upload
storeFile=/Users/you/conversation-coach-upload.jks
```
Wire it into `android/app/build.gradle.kts` `signingConfigs`/`buildTypes`
(see flutter.dev/deployment/android), then:
```bash
flutter build apk --release
```

### Easier invite flow (optional)
**Firebase App Distribution** lets you upload an APK and invite partners by
email; they get a link and install. Good middle ground before Google Play.

---

## 3. iOS — TestFlight (after enrolling)

1. **Enrol** in the Apple Developer Program ($99/yr) at developer.apple.com.
2. In Xcode (`ios/Runner.xcworkspace`): set **Team** + **Bundle Identifier**,
   bump **Version**/**Build**. The mic usage string and background-audio mode
   are already in `Info.plist`.
3. Target **"Any iOS Device (arm64)"** → **Product → Archive**.
4. In the Organizer: **Distribute App → App Store Connect → Upload**.
5. In **App Store Connect → your app → TestFlight**:
   - Add **internal testers** (people on your team) — installs almost
     immediately, no review.
   - Or **external testers** (your partners by email) — requires a short
     **Beta App Review** first, then they install.
6. Partners install the **TestFlight** app, accept the invite, and install.

### App Store Connect will ask:
- **Export compliance** — the app uses standard HTTPS/encryption; typically
  qualifies for the exemption (answer the encryption questions accordingly).
- **App Privacy** — declare: microphone/audio usage; audio + transcript text are
  sent to Anthropic/OpenAI **only on opt-in** for analysis/transcription;
  everything else stays on-device, encrypted. Nothing is collected by you.

---

## 4. Privacy & consent (ships in-app already)

- Recordings and the database are encrypted at rest (SQLCipher + OS keystore).
- A mandatory, localised consent step precedes every recording; a visible
  recording indicator is shown while live; there is no hidden recording.
- Retention (auto-delete audio after N days) and a real "wipe everything" are in
  Settings → Privacy & data.

Mention to partners: enabling **Cloud — Whisper** sends their audio to OpenAI for
transcription, and analysis sends transcript **text** to Anthropic. Both are
opt-in and use the partner's own keys.

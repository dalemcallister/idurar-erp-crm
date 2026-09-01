# Ship an iOS test build to a remote friend (TestFlight)

iOS has no "send them an APK" — a testable build must go through **TestFlight**,
which needs the paid **Apple Developer Program** (~$99/year). Once set up, your
friend just taps an email/link, installs the **TestFlight** app, and gets the
build (and every future update) automatically.

App identity for this project:
- **Name:** Conversation Coach
- **Bundle ID:** `com.mcallister.clariconvo` (set this in Xcode — see BRANDING.md)

---

## One-time setup

### 1. Enrol in the Apple Developer Program
<https://developer.apple.com/programs/enroll/> — sign in with your Apple ID,
pay the fee. Approval is usually minutes to ~24–48h. You can't upload a build
until this is active.

### 2. Set the bundle ID and signing team in Xcode
```bash
cd ~/idurar-erp-crm/conversation_coach
open ios/Runner.xcworkspace
```
In Xcode: select the **Runner** target → **Signing & Capabilities**:
- **Team:** pick your Apple Developer team.
- **Bundle Identifier:** `com.mcallister.clariconvo`.
- Leave **Automatically manage signing** ticked — Xcode creates the signing
  certificate and provisioning profile for you.

### 3. Create the app record in App Store Connect
<https://appstoreconnect.apple.com> → **Apps → +** → **New App**:
- Platform: iOS
- Name: `Conversation Coach` (must be unique across the App Store — if taken,
  append something, e.g. `Conversation Coach – Beta`; the on-phone name stays
  "Conversation Coach")
- Primary language, and select the bundle ID `com.mcallister.clariconvo`
- SKU: any string, e.g. `conversation-coach`

---

## Every time you want to push a new test build

### 4. Bump the build number
TestFlight rejects a re-used build number. In `pubspec.yaml` the version is
`2.0.0+N` — the number **after the `+`** is the build. Bump it each upload
(`2.0.0+4`, `2.0.0+5`, …). Any Dart/Podfile/Gradle change needs a fresh build
uploaded — the store never pushes code changes on its own.

### 5. Build the signed .ipa
```bash
flutter build ipa --dart-define=HUGGINGFACE_TOKEN=hf_xxxxx
```
The `--dart-define` is required so the app can download the (gated) on-device
Gemma model; without it the download 401s on the tester's phone. This produces
`build/ios/ipa/conversation_coach.ipa`. (If signing errors appear, open the
workspace and archive from Xcode instead: **Product → Archive**.)

### 6. Upload to App Store Connect
Easiest: open the free **Transporter** app (Mac App Store), sign in with your
Apple ID, drag in the `.ipa`, click **Deliver**.
Alternative: Xcode **Organizer** (Window → Organizer) → select the archive →
**Distribute App → App Store Connect → Upload**.

The build then "processes" for ~5–15 minutes before it appears in TestFlight.

---

## Get it to your friend (external tester)

In App Store Connect → your app → **TestFlight** tab:

1. Because your friend isn't on your team, add them as an **external** tester:
   under **Testers & Groups**, create a group (e.g. "Friends"), then add their
   email address.
2. Fill in the required **Test Information** (a sentence on what to test, your
   contact email). Export compliance is already handled — the app declares
   `ITSAppUsesNonExemptEncryption = false`, so you won't be asked each time.
3. The **first** external build needs a one-time **Beta App Review** (usually
   under 24h). Later builds to the same group go out immediately.
4. Your friend gets an email invite → they install the **TestFlight** app from
   the App Store → tap the invite → install Conversation Coach.

Builds expire **90 days** after upload; just upload a fresh build to renew.

---

## What your tester needs to know (v2 — fully on-device)

No accounts, no API keys, no shared backend. Everything runs on the phone.
First-run steps for the tester:

1. Open the app → **Settings → On-device models → Download analysis model**
   (Gemma, ~2.4 GB — do it on Wi-Fi; it's a one-time download). The
   transcription model (Whisper, ~148 MB) downloads automatically the first
   time they record.
2. Set a goal, record a conversation, and the whole pipeline
   (transcribe → analyse → Ask) runs locally.

Privacy: the audio and transcript never leave the device — only the tester's
own phone does the analysis.

> Note: the app currently ships with a HuggingFace token baked in at build time
> (`--dart-define`) purely to fetch the gated model. Swap to an un-gated model
> before any wide/public distribution so no token ships (PROJECT.md roadmap #6).

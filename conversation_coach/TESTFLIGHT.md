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
TestFlight rejects a re-used build number. In `pubspec.yaml`, the version is
`0.1.0+1` — the number **after the `+`** is the build. Bump it each upload
(`0.1.0+2`, `0.1.0+3`, …).

### 5. Build the signed .ipa
```bash
flutter build ipa
```
This produces `build/ios/ipa/conversation_coach.ipa`. (If signing errors appear,
open the workspace and archive from Xcode instead: **Product → Archive**.)

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

## What your friend needs to know (bring-your-own-key)

There's no shared backend — each tester uses their **own** API keys, entered
in-app:

- **Settings → Model & provider → Add key** — an **Anthropic** key (for the
  Claude analysis). Without it the app runs on the built-in **offline demo**
  (canned analysis), which is fine for a first look.
- **Settings → Transcription engine → Cloud (Whisper) → Add key** — an
  **OpenAI** key, to transcribe the real recording. Without it, transcription
  uses the demo transcript.
- Keys are stored only in the iOS Keychain, never in the app's data or sent
  anywhere except the provider they belong to.
- If you set a **prepaid budget** (Settings → Spending budget), each analysed
  session draws it down — make sure there's headroom or recording is gated.

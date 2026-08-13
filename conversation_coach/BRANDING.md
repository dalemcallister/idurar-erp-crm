# Branding

The app is branded **Conversation Coach** with a teal speech‑bubble + waveform
launcher icon. Most branding is committed; two things must be set on your Mac
because the Gradle/Xcode project files are generated locally and aren't tracked
in this repo.

## What's already done (committed)

- **Display name** — `Conversation Coach`
  - Android: `android:label` in `android/app/src/main/AndroidManifest.xml`
  - iOS: `CFBundleDisplayName` in `ios/Runner/Info.plist`
- **Launcher icon source** — `assets/icon/app_icon.png` (full‑bleed) and
  `assets/icon/app_icon_foreground.png` (Android adaptive foreground).
- **Icon generator config** — `flutter_launcher_icons` block in `pubspec.yaml`.

## 1. Generate the launcher icons (run once on your Mac)

```bash
cd conversation_coach
flutter pub get
dart run flutter_launcher_icons
```

This writes the iOS `AppIcon.appiconset` and the Android `mipmap-*` / adaptive
icon resources. Rebuild the app to see the new icon. To replace the placeholder
later, drop a 1024×1024 PNG over `assets/icon/app_icon.png` (and a transparent
version over `app_icon_foreground.png`) and re‑run the command.

## 2. Set the bundle / application ID → `com.mcallister.clariconvo`

This is the permanent unique ID for the App Store / Play Store. It lives in the
locally‑generated project files (not committed), so set it on your Mac:

**Android** — `android/app/build.gradle.kts`, in the `defaultConfig` block:

```kotlin
applicationId = "com.mcallister.clariconvo"
```

(Leave `namespace` as is — it only affects the generated `R`/`BuildConfig`
classes and doesn't need to match the applicationId.)

**iOS** — easiest in Xcode:

```bash
open ios/Runner.xcworkspace
```

Select the **Runner** target → **Signing & Capabilities** → set
**Bundle Identifier** to `com.mcallister.clariconvo`, and pick your Apple
Developer team there too. (Equivalent to setting `PRODUCT_BUNDLE_IDENTIFIER`
in `ios/Runner.xcodeproj/project.pbxproj`.)

## 3. Rebuild

```bash
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter run            # or: flutter build apk --release
```

# Kotlin Multiplatform Quickstart

> **DocC mirror:** Also available as the `KMPIntegration` article and tutorial chapters 9 ("KMP Setup") and 10 ("KMP Dual-Store Release") in the `ShipItKit` DocC archive.

Ship a Kotlin Multiplatform Mobile (KMP) app to both the App Store and Google Play from a single Shipfile.

## What you get

- One source tree → both `.ipa` and `.aab`
- The same App Store Connect / Google Play distribution pipeline as native projects
- Automatic detection from `build.gradle.kts`
- Shared version source via `gradle.properties` (`versionName` + `versionCode`)

## Prerequisites

- Xcode 15+ with command-line tools (`xcode-select --install`)
- JDK 17+ on PATH (`java -version`)
- A working KMP project produced by [JetBrains' KMP wizard](https://kmp.jetbrains.com/) or the `kmm-application` template — i.e. a layout like:
  ```
  ./
    gradlew
    settings.gradle.kts
    build.gradle.kts          # applies kotlin("multiplatform")
    shared/
      build.gradle.kts        # the shared multiplatform module
    androidApp/
      build.gradle.kts        # the Android wrapper
    iosApp/
      iosApp.xcodeproj or .xcworkspace
  ```
- A Google Play service account JSON key (for Play Store uploads)
- App Store Connect API key (for TestFlight uploads)

## 1. Detect the project

From the project root, run:

```bash
shipit inspect
```

You should see:

```
detectedPlatform: ios
detectedBuildSystem: kmp
buildSystemFiles:
  - build.gradle.kts
  - settings.gradle.kts
```

If `detectedBuildSystem` is empty, ensure your root `build.gradle.kts` applies `kotlin("multiplatform")` or the `org.jetbrains.kotlin.multiplatform` plugin.

## 2. Write a Shipfile

```yaml
# Shipfile.yml
app:
  scheme: iosApp                  # the Xcode scheme for the iOS wrapper
  workspace: iosApp/iosApp.xcworkspace
  bundle_id: com.example.iosApp
  team_id: ABCD123456

ios:
  build_system: kmp
android:
  build_system: kmp
  module: androidApp
  package_name: com.example.androidapp
  play_track: internal

versioning:
  source: kmp                     # read versionName/versionCode from gradle.properties
  spec_path: gradle.properties

workflows:
  beta-ios:
    - action: test
      options: { platform: ios }
    - action: archive
      options: { platform: ios }
    - action: testflight
  beta-android:
    - action: test
      options: { platform: android }
    - action: archive
      options: { platform: android }
    - action: play-store
```

And make sure your `gradle.properties` contains the version keys:

```properties
# gradle.properties
versionName=1.0.0
versionCode=1
```

## 3. Run doctor

```bash
shipit doctor
```

Doctor adds toolchain probes when a non-`native` build system is resolved:

```
✓ Xcode installed
✓ xcodebuild available
✓ git on PATH
✓ java on PATH (for Gradle/Kotlin)
✓ gradlew present in project root
```

If `java` or `./gradlew` is missing, fix that before proceeding — neither the iOS nor Android KMP path can run without them.

## 4. Build each platform

```bash
# iOS — runs `gradlew :shared:linkReleaseFrameworkIosSimulatorArm64` then xcodebuild
shipit build --platform ios

# Android — regular Gradle path against the android module
shipit build --platform android
```

The iOS path links the `Shared.framework` first, then invokes `xcodebuild` against the wrapper `iosApp.xcworkspace`. The Android path is identical to a native Android Gradle build.

## 5. Bump the shared version

```bash
shipit version bump --component build
```

With `versioning.source: kmp`, this writes to `gradle.properties` instead of `Info.plist` / `agvtool` / `.xcodeproj`. Both targets pick up the new value on the next build.

## 6. Run a full release workflow

```bash
shipit run beta-ios       # test → archive (.ipa) → TestFlight
shipit run beta-android   # test → archive (.aab) → Play Store
```

## Common pitfalls

| Symptom | Likely cause | Fix |
|---|---|---|
| `xcodebuild` reports `Shared.framework not found` | Framework wasn't linked before `xcodebuild` | Make sure `ios.build_system: kmp` is set so `ensureProjectGenerated()` runs the link |
| Wrong simulator architecture during `link…Framework…` | Targeting Intel sim on Apple silicon (or vice versa) | Use the default `IosSimulatorArm64` target, or pass `options.module` plus a `gradlew :shared:link…X64` task explicitly |
| `versionName` not updated | Custom key names in `gradle.properties` | Override via `versioning.marketing_key` / `versioning.build_key` |
| Gradle re-links the framework every run | Expected — the Gradle task is incremental and skips itself when inputs are unchanged | No action needed |

## Next steps

- [KMP Integration article](../Sources/ShipItKit/ShipItKit.docc/Articles/KMPIntegration.md) — deeper dive on the pipeline architecture
- [`docs/configuration-reference.md#build-systems`](configuration-reference.md#build-systems) — the full `build_system` reference
- [`docs/ci-setup.md`](ci-setup.md) — KMP-on-CI checklist

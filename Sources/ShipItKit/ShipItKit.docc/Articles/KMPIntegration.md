# Kotlin Multiplatform integration

Ship a Kotlin Multiplatform Mobile project to the App Store and Google Play from a single Shipfile.

## Overview

Kotlin Multiplatform (KMP) projects produce two artifacts from one source tree: an iOS `.framework` (and the Xcode wrapper that hosts it) and a regular Android `.aab`. ShipItKit models this with **two orthogonal axes** on ``ResolvedConfig``:

| Axis | Type | Set per | Meaning |
|---|---|---|---|
| ``Platform`` | `.ios` / `.android` | invocation (`--platform`) | which side of the distribution pipeline to run |
| ``BuildSystem`` | `.native` / `.kmp` / `.flutter` / `.reactNative` | `ios.build_system:` / `android.build_system:` | how the native artifact is compiled before distribution |

A native iOS project is `Platform.ios` + `BuildSystem.native`. A KMP project is `Platform.ios` (or `.android`) + `BuildSystem.kmp`. ``BuildAction``, ``ArchiveAction``, and ``TestAction`` dispatch on ``BuildSystem`` because they compile or validate target artifacts. Later distribution actions (``SignAction``, ``ExportAction``, ``TestFlightAction``, ``PlayStoreAction``, ``UploadAction``) remain artifact-path driven.

## How the iOS path works

When the resolved iOS build system is ``BuildSystem/kmp``, the build and archive actions link the KMP framework before invoking `xcodebuild`:

```
BuildAction   → gradlew :shared:linkReleaseFrameworkIosSimulatorArm64 → xcodebuild build
ArchiveAction → gradlew :shared:linkReleaseFrameworkIosArm64          → xcodebuild archive
```

``BuildAction`` defaults to the simulator target (`IosSimulatorArm64`) for local builds. ``ArchiveAction`` defaults to the device target (`IosArm64`) for App Store archives. Override the module and target with `ios.kmp_shared_module`, `ios.kmp_build_target`, and `ios.kmp_archive_target` when your project does not use the standard KMP layout.

The Gradle link task is incremental — re-running it on an unchanged shared module is essentially free.

## How the Android path works

The KMP Android target is a regular Android Gradle module. ``BuildAction`` and ``ArchiveAction`` dispatch to the same code that drives `BuildSystem.native` Android builds: `gradlew :<module>:assembleRelease` for APKs, `gradlew :<module>:bundleRelease` for AABs.

## Versioning

KMP projects typically keep their version in `gradle.properties`:

```properties
versionName=1.2.3
versionCode=45
```

Set ``ResolvedConfig/versioningSource`` to `"kmp"` (`source: kmp` in Shipfile) and ShipItKit will read/write those keys directly. Bumping the build number via ``VersionBumper`` updates `versionCode`; bumping the marketing version updates `versionName`. The next `gradlew` invocation picks up the new values on both targets.

Custom key names are supported via `versioning.marketing_key` and `versioning.build_key`.

## Test action

For KMP iOS tests, ``TestAction`` dispatches to `gradlew :shared:iosSimulatorArm64Test` rather than `xcodebuild test`. Override it with `ios.kmp_test_task` and `ios.kmp_shared_module` when needed. The Android side reuses the native unit-test path with a module-qualified Gradle task.

## Minimal Shipfile

```yaml
app:
  scheme: iosApp
  workspace: iosApp/iosApp.xcworkspace
  bundle_id: com.example.iosApp
  team_id: ABCD123456

ios:
  build_system: kmp
  kmp_shared_module: shared
  kmp_build_target: IosSimulatorArm64
  kmp_archive_target: IosArm64
  kmp_test_task: iosSimulatorArm64Test
android:
  build_system: kmp
  module: androidApp
  gradle_project_dir: .
  package_name: com.example.androidapp

versioning:
  source: kmp
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

## Auto-detection

When `build_system` is omitted, ``ConfigResolver`` activates KMP automatically from Gradle markers. ``ProjectInspector`` can also report Flutter and React Native markers, but those remain inspection-only until runtime support ships.

| Project marker | Detected value |
|---|---|
| `build.gradle.kts` applying `kotlin("multiplatform")` or `org.jetbrains.kotlin.multiplatform` | `.kmp` |
| `pubspec.yaml` containing `flutter:` | `.flutter` reported by inspection only |
| `package.json` containing `react-native` | `.reactNative` reported by inspection only |

The same `BuildSystem` value applies to both iOS and Android in a single project — you cannot have an iOS KMP wrapper alongside a native Android Gradle module from the same Shipfile; that's two projects.

## CI requirements

KMP iOS builds need both `xcodebuild` and `gradlew`, so they run on macOS runners with a JDK 17+ available. Android-only KMP builds can run from Linux as long as JDK 17+ and the Android SDK are installed.

The `doctor` command adds two probes when the resolved build system is `.kmp`:

- `java on PATH (for Gradle/Kotlin)`
- `gradlew present in project root`

These fire only when needed; pure-native projects don't see them.

## Topics

### Core types

- ``BuildSystem``
- ``IOSConfig/buildSystem``
- ``IOSConfig/kmpSharedModule``
- ``IOSConfig/kmpBuildTarget``
- ``IOSConfig/kmpArchiveTarget``
- ``IOSConfig/kmpTestTask``
- ``AndroidConfig/buildSystem``
- ``AndroidConfig/gradleProjectDir``
- ``ResolvedConfig/iosBuildSystem``
- ``ResolvedConfig/androidBuildSystem``

### Auto-detection

- ``BuildSystem/autoDetect(in:fileManager:)``
- ``ProjectInspection/detectedBuildSystem``
- ``ProjectInspection/buildSystemFiles``

### Related

- <doc:Architecture>
- <doc:ConfigurationReference>
- <doc:Versioning>
- <doc:AndroidAndGooglePlay>

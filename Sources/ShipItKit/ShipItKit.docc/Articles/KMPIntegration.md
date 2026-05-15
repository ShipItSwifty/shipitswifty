# Kotlin Multiplatform integration

Ship a Kotlin Multiplatform Mobile project to the App Store and Google Play from a single Shipfile.

## Overview

Kotlin Multiplatform (KMP) projects produce two artifacts from one source tree: an iOS `.framework` (and the Xcode wrapper that hosts it) and a regular Android `.aab`. ShipItKit models this with **two orthogonal axes** on ``ResolvedConfig``:

| Axis | Type | Set per | Meaning |
|---|---|---|---|
| ``Platform`` | `.ios` / `.android` | invocation (`--platform`) | which side of the distribution pipeline to run |
| ``BuildSystem`` | `.native` / `.kmp` / `.flutter` / `.reactNative` | `ios.build_system:` / `android.build_system:` | how the native artifact is compiled before distribution |

A native iOS project is `Platform.ios` + `BuildSystem.native`. A KMP project is `Platform.ios` (or `.android`) + `BuildSystem.kmp`. The downstream distribution actions (``SignAction``, ``ArchiveAction``, ``ExportAction``, ``TestFlightAction``, ``PlayStoreAction``, ``UploadAction``) are **artifact-path driven** and do not change behaviour across build systems.

## How the iOS path works

When the resolved iOS build system is ``BuildSystem/kmp``, ``ActionContext/ensureProjectGenerated()`` runs the KMP framework link task *before* any `xcodebuild` step:

```
ensureProjectGenerated() → gradlew :shared:linkReleaseFrameworkIosSimulatorArm64
                         → (existing project generation, if configured)
                         → ready for xcodebuild
```

``BuildAction`` and ``ArchiveAction`` then invoke `xcodebuild` against the wrapper `iosApp.xcworkspace`. Because the framework was already linked, Xcode resolves `Shared.framework` without errors.

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

For KMP iOS tests, ``TestAction`` dispatches to `gradlew :shared:iosSimulatorArm64Test` rather than `xcodebuild test`. This is the convention KMP projects use to run the Kotlin-side test suite on an iOS-like target. The Android side reuses the native unit-test path.

## Minimal Shipfile

```yaml
app:
  scheme: iosApp
  workspace: iosApp/iosApp.xcworkspace
  bundle_id: com.example.iosApp
  team_id: ABCD123456

ios:
  build_system: kmp
android:
  build_system: kmp
  module: androidApp
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

When `build_system` is omitted, ``ProjectInspector`` and ``ConfigResolver`` agree on a single rule:

| Project marker | Detected value |
|---|---|
| `build.gradle.kts` applying `kotlin("multiplatform")` or `org.jetbrains.kotlin.multiplatform` | `.kmp` |

The same `BuildSystem` value applies to both iOS and Android in a single project — you cannot have an iOS KMP wrapper alongside a native Android Gradle module from the same Shipfile; that's two projects.

## CI requirements

KMP iOS builds need both `xcodebuild` and `gradlew`, so they run on macOS runners with a JDK 17+ available. Android-only KMP builds can run from Linux as long as JDK 17+ and the Android SDK are installed.

The ``DoctorCommand`` adds two probes when the resolved build system is `.kmp`:

- `java on PATH (for Gradle/Kotlin)`
- `gradlew present in project root`

These fire only when needed; pure-native projects don't see them.

## Topics

### Core types

- ``BuildSystem``
- ``IOSConfig/buildSystem``
- ``AndroidConfig/buildSystem``
- ``ResolvedConfig/iosBuildSystem``
- ``ResolvedConfig/androidBuildSystem``

### Gradle tasks

- ``GradleTask/linkReleaseFrameworkIosArm64``
- ``GradleTask/linkReleaseFrameworkIosSimulatorArm64``
- ``GradleTask/linkDebugFrameworkIosArm64``
- ``GradleTask/embedAndSignAppleFrameworkForXcode``
- ``GradleTask/iosSimulatorArm64Test``
- ``GradleTask/iosArm64Test``
- ``GradleTask/linkFramework(configuration:target:)``

### Auto-detection

- ``BuildSystem/autoDetect(in:fileManager:)``
- ``ProjectInspection/detectedBuildSystem``
- ``ProjectInspection/buildSystemFiles``

### Related

- <doc:Architecture>
- <doc:ConfigurationReference>
- <doc:Versioning>
- <doc:AndroidAndGooglePlay>

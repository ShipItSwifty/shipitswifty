# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Kotlin Multiplatform (KMP) support.** A new `BuildSystem` enum (`native`, `flutter`, `react_native`, `kmp`) is configurable per platform via `ios.build_system:` and `android.build_system:` (or `SHIPIT_IOS__BUILD_SYSTEM` / `SHIPIT_ANDROID__BUILD_SYSTEM`). KMP iOS builds run `gradlew :shared:link…Framework…` automatically before `xcodebuild` via `ActionContext.ensureProjectGenerated()`. KMP Android builds reuse the native Gradle path. Distribution actions (`sign`, `archive`, `export`, `testflight`, `play-store`, `upload`, `dsym`, `frame`, `screenshot`) are unchanged across build systems.
- `BuildSystem.autoDetect(in:fileManager:)` infers the build system from project files (`pubspec.yaml` → `flutter`, `package.json` with `react-native` → `react_native`, `kotlin("multiplatform")` in `build.gradle.kts` → `kmp`).
- `ProjectInspector` now reports `detectedBuildSystem` and `buildSystemFiles` so `shipit inspect` and `shipit ai-session` can surface the resolved value.
- `KMPVersionSource` reads and writes `versionName` / `versionCode` in `gradle.properties`; opt in with `versioning.source: kmp`.
- New `GradleTask` statics for KMP: `linkDebugFrameworkIosArm64`, `linkReleaseFrameworkIosArm64`, `linkDebugFrameworkIosSimulatorArm64`, `linkReleaseFrameworkIosSimulatorArm64`, `linkDebugFrameworkIosX64`, `linkReleaseFrameworkIosX64`, `embedAndSignAppleFrameworkForXcode`, `iosSimulatorArm64Test`, `iosArm64Test`, `iosX64Test`, plus a `linkFramework(configuration:target:)` helper.
- `shipit doctor` adds conditional toolchain probes (`java`, `gradlew`, and — in upcoming releases — `flutter`, `node`, `npx`) when a non-`native` build system is resolved.
- New DocC article `KMPIntegration` and tutorial chapter "Kotlin Multiplatform" (chapters 9 and 10). New markdown quickstart `docs/kmp-quickstart.md` and CI guide section in `docs/ci-setup.md`.
- Added `CHANGELOG.md` to track notable project changes.

### Notes
- Flutter and React Native `build_system` values are accepted by the schema but produce a clear `invalidConfiguration` error at build time — they are planned for upcoming releases.
- The `Platform` enum (`ios` / `android`) is unchanged. Cross-platform frameworks are modeled via the orthogonal `BuildSystem` axis so `Platform` keeps its meaning of "which target-OS pipeline runs."

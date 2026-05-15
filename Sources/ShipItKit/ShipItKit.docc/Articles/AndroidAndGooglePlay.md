# Android & Google Play

Build, validate, and ship Android apps with the same Shipfile-driven model as iOS.

## Overview

ShipItKit treats Android as a first-class platform. The same actions you use for iOS — `build`, `test`, `lint`, `archive`, `coverage`, `validate` — exist for Android, plus ``PlayStoreAction`` for upload. The platform is selected per-Shipfile (`platform: android`) or per-command (`--platform android`).

## Prerequisites

- macOS or Linux with **JDK 17+**.
- A Gradle-based Android project with `gradlew`.
- For uploads: a Google Play **service-account JSON**.

## Credentials

| Env var | Purpose |
|---|---|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Raw service-account JSON — **preferred for CI** |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Path to the JSON file — **preferred locally** |

The service account needs the `Release manager` role on the app in the Play Console.

If you need help locating `package_name`, choosing `play_track`, or setting up the service account, see <doc:CredentialLookup>.

## Minimal Shipfile

```yaml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp
  play_track: internal

workflows:
  beta:
    - action: lint
    - action: test
    - action: archive          # produces .aab
    - action: play-store
      options:
        track: internal
        rollout_fraction: 1.0
```

## Build & test

| Action | Gradle task it runs |
|---|---|
| ``BuildAction`` | `./gradlew assemble<Variant>` |
| ``TestAction`` | `./gradlew test<Variant>UnitTest` (and instrumented tests when configured) |
| ``LintAction`` | `./gradlew lint<Variant>` |
| ``ArchiveAction`` | `./gradlew bundle<Variant>` (AAB) or `assemble` (APK) |
| ``CoverageAction`` | Reads `jacocoTestReport` XML output |

Flavors are first-class: pass `flavor` (CLI: `--flavor`) and ShipItKit composes the right `assembleFreeRelease`-style task name.

## Typed Gradle wrapper

Internally every Gradle invocation goes through `Gradle`, which builds the command line from typed values:

```swift
let output = try await Gradle(context: context.shell)
    .task(.assembleRelease)
    .property(.custom(key: "stage", value: "production"))
    .flag(.noDaemon)
    .run()
```

See `GradleTask`, `GradleProperty`, and `GradleFlag`.

## Google Play upload

``PlayStoreAction`` wraps the Google Play Developer API v3's transactional model:

1. Create an **edit** session.
2. Upload the AAB or APK.
3. Assign to a track (`internal` / `alpha` / `beta` / `production`).
4. Set per-locale release notes.
5. Optionally set a staged rollout fraction.
6. **Commit** the edit (atomic).

```bash
shipit play-store \
  --bundle ./app/build/outputs/bundle/release/app-release.aab \
  --track beta \
  --rollout-fraction 0.1 \
  --release-notes en-US:"Bug fixes and improvements"
```

If anything fails before commit, the edit is discarded and Play state is unchanged.

## AAB validation

Run static validation against an AAB before uploading:

```bash
shipit validate bundle --bundle ./app/build/outputs/bundle/release/app-release.aab
```

This checks `packageName`, `versionCode` monotonicity, signing block, and manifest sanity. See <doc:Validation>.

## Coverage

```bash
shipit coverage --platform android \
  --report ./app/build/reports/jacoco/test/jacocoTestReport.xml
```

Returns the same ``CoverageAction/Result`` shape as iOS — first-party filtering, per-module breakdown, JSON & Markdown formats. See <doc:Coverage>.

## SDK helpers

When you need to drive the SDK directly:

- `Adb` — typed `adb` wrapper.
- `Emulator` — typed `emulator` wrapper for headless CI runs.
- `Bundletool` — typed `bundletool` wrapper for AAB inspection.

## CI integration

```yaml
# .github/workflows/release.yml
- uses: actions/setup-java@v5
  with: { java-version: '17', distribution: 'temurin' }
- run: shipit run beta --ci --output json
  env:
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.GOOGLE_PLAY_JSON }}
```

See <doc:CIIntegration>.

## See also

- ``PlayStoreAction``
- ``GooglePlayClient``
- ``GooglePlayUploadService``
- ``GooglePlayJWTGenerator``
- ``GooglePlayEdit``
- ``GooglePlayBundle``
- ``GooglePlayApk``
- `Gradle`
- `Bundletool`
- `Adb`
- `Emulator`
- <doc:CredentialLookup>
- <doc:Validation>
- <doc:Coverage>

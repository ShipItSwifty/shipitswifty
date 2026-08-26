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

If you need help locating `package_name` or setting up the service account, see <doc:CredentialLookup>.

## Minimal Shipfile

```yaml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp

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
| ``TestAction`` | `./gradlew test<Variant>UnitTest` (unit) or `connectedAndroidTest` (instrumented) |
| ``LintAction`` | `./gradlew lint<Variant>` |
| ``ArchiveAction`` | `./gradlew bundle<Variant>` (AAB) or `assemble` (APK) |
| ``CoverageAction`` | Reads `jacocoTestReport` XML output |

Flavors are first-class: pass `flavor` (CLI: `--flavor`) and ShipItKit composes the right `assembleFreeRelease`-style task name.

### Test kinds and device strategies

The test action supports three **kinds** (`unit`, `instrumented`, `e2e`) and four **device strategies** (`none`, `connected`, `named_emulators`, `managed`):

```yaml
# Unit tests — no device needed
- action: test
  options:
    kind: unit
    scope: module
    module: app

# Instrumented tests with explicit emulators
- action: test
  options:
    kind: instrumented
    scope: root
    devices:
      strategy: named_emulators
      emulators:
        - Pixel_9_API_35
      prompt_locally: true

# Instrumented tests with Gradle Managed Devices
- action: test
  options:
    kind: instrumented
    scope: module
    module: app
    devices:
      strategy: managed
      group: phoneAndTablet
```

When `kind` is `instrumented` and `devices.strategy` is `named_emulators`, ShipIt boots the listed AVDs before running the test task and tears them down after. When `prompt_locally` is `true` and the run is interactive (not CI), ShipIt prompts the developer to select from available emulators if none are configured or if the configured AVD names are not available locally.

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

## AndroidCLI preview integration

ShipIt also provides optional support for Google's preview AndroidCLI. AndroidCLI complements the release pipeline with project description, layout and screen inspection, emulator and SDK management, documentation search, skills, and Android Studio integration. It does not replace Gradle compilation, tests, lint, archives, signing, or Play Store upload.

Use the direct passthrough without changing your Shipfile:

```bash
shipit android-cli describe
shipit android-cli emulator list
shipit android-cli layout --pretty
shipit android-cli skills list --long
```

To use the `android-*` actions in workflows, opt in explicitly:

```yaml
android:
  cli:
    enabled: true
    executable_path: android
    sdk_path: /opt/android-sdk

workflows:
  inspect:
    - action: android-describe
      options: { operation: describe, arguments: ["--json"] }
    - action: android-layout
      options: { operation: layout, arguments: ["--pretty"] }
```

Environment- or device-changing operations such as creating projects, installing APKs, changing SDK packages, adding skills, or updating AndroidCLI require `allow_mutation: true`. ShipIt validates AndroidCLI 1.0 or newer when workflow integration is enabled and never installs or updates AndroidCLI or its skills automatically.

AndroidCLI is preview software. Keep `android.cli.enabled` off when it is unavailable or when a workflow requires the established Gradle/ADB behavior. AndroidCLI emulator management is currently unavailable on Windows.

### AndroidCLIKit

Swift scripts can depend on `AndroidCLIKit` directly:

```swift
import AndroidCLIKit

let output = try await AndroidCLI()
    .emulatorList(arguments: ["--long"])
    .run()

print(output.stdout)
```

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
- `AndroidCLI`
- <doc:CredentialLookup>
- <doc:Validation>
- <doc:Coverage>

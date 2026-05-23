# Configuration Reference

Complete reference for all `Shipfile.yml` keys and environment variables.

## Overview

ShipItSwifty is configured via a `Shipfile.yml` at your project root. All string values support `${ENV_VAR}` expansion. CLI flags override everything; environment variables (`SHIPIT_*`) override the file.

## Top-level Structure

```yaml
app:          # App identity and Xcode project settings
app_store_connect:  # ASC API credentials
code_signing: # Code signing configuration
build:        # xcodebuild build settings
archive:      # Archive and export settings
export:       # IPA export settings
testflight:   # TestFlight distribution settings
screenshots:  # Screenshot capture settings
metadata:     # App Store metadata settings
versioning:   # Version bump strategy
notifications: # Notification settings
workflows:    # Named workflow definitions
```

## `app`

Core app identity.

| Key | Type | Description |
|---|---|---|
| `workspace` | string | Path to `.xcworkspace` |
| `project` | string | Path to `.xcodeproj` (used when `workspace` is nil) |
| `scheme` | string | Xcode scheme for build and test |
| `bundle_id` | string | App bundle identifier. Optional if it can be inferred from Xcode build settings |
| `team_id` | string | Apple Developer Team ID. Optional if it can be inferred from Xcode build settings |

## `app_store_connect`

App Store Connect API credentials.

For App Store Connect API actions, provide `key_id`, `issuer_id`, and exactly one private key source: `private_key` or `key_path`.

`issuer_id` is not inside the `.p8` file. Copy it from the App Store Connect API Keys page.

You can omit this whole section if you only use local Xcode actions such as `build`, `test`, `archive`, or `export`.

Find these values in App Store Connect:
1. Open `Users and Access`.
2. Open `Integrations`.
3. Open `App Store Connect API`.
4. Create or select an API key.
5. Copy `Key ID` and `Issuer ID`.
6. Download the `.p8` file and use it via `private_key` or `key_path`.

| Key | Type | Description |
|---|---|---|
| `key_id` | string | API key ID (also: `ASC_KEY_ID` env var) |
| `issuer_id` | string | Issuer ID (also: `ASC_ISSUER_ID` env var) |
| `key_path` | string | Path to `.p8` key file (local dev only) |
| `private_key` | string | Raw `.p8` key contents (use env var: `ASC_PRIVATE_KEY`) |

## `code_signing`

Code signing configuration.

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | string | `vault` | `automatic`, `vault`, or `manual` |
| `storage` | string | `git` | `git`, `s3`, or `gcs` |
| `git_url` | string | — | URL of the encrypted certificate repo |
| `app_identifier` | string | — | Bundle ID for cert/profile matching |
| `profile_type` | string | — | `appstore`, `adhoc`, `development` |

For `vault` storage, also set `VAULT_PASSWORD` in your environment.

With `type: automatic`, ShipIt lets Xcode manage signing by passing `-allowProvisioningUpdates` during build/archive/export and by exporting with `signingStyle` set to `automatic`.

## `build`

xcodebuild build settings.

| Key | Type | Default | Description |
|---|---|---|---|
| `configuration` | string | `Release` | Build configuration name |
| `derived_data_path` | string | — | Custom derived data directory |
| `xcargs` | map | `{}` | Additional flags passed to `xcodebuild` |

## `test`

Test action configuration. Works across all platforms (iOS, Android, Flutter, React Native, KMP).

| Key | Type | Default | Description |
|---|---|---|---|
| `scheme` | string | from `app.scheme` | Xcode scheme containing test targets (iOS) |
| `destinations` | [string] | auto-discovered | List of xcodebuild destination strings (iOS) |
| `destination` | string | — | Single destination (backward compat; prefer `destinations`) |
| `configuration` | string | `Debug` | Build configuration (iOS) |
| `test_plan` | string | — | Xcode test plan name (iOS) |
| `only_testing` | [string] | — | Restrict to specific test targets/cases (iOS) |
| `skip_testing` | [string] | — | Skip specific test targets/cases (iOS) |
| `enable_code_coverage` | bool | `false` | Collect code coverage (iOS) |
| `result_bundle_path` | string | — | Custom `.xcresult` output path (iOS) |
| `retry_on_failure` | bool | `false` | Enable Xcode's `-retry-tests-on-failure` (iOS) |
| `kind` | string | `unit` | Test kind: `unit`, `instrumented`, `e2e` (Android) |
| `scope` | string | `module` | Gradle task scope: `module` or `root` (Android) |
| `module` | string | from config | Gradle module to test (Android/KMP) |
| `build_variant` | string | `debug` | Gradle build variant (Android) |
| `task` | string | — | Explicit Gradle task name override (Android) |
| `devices` | object | — | Device config for instrumented tests (Android) |
| `infrastructure_retry` | object | — | Cross-platform infrastructure retry. See below. |

### `infrastructure_retry`

Retries the entire test invocation for transient infrastructure failures. Each platform has its own failure classifier that distinguishes real test failures from infrastructure problems (simulator crashes, emulator disconnects, tool crashes, worker OOMs).

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Enable infrastructure retries |
| `max_attempts` | int | `3` | Maximum total attempts including the first |
| `initial_delay_seconds` | number | `2` | Delay before first retry (exponential backoff with ±25% jitter) |
| `max_delay_seconds` | number | `60` | Maximum delay cap |

```yaml
test:
  test_plan: Novalingo
  retry_on_failure: true
  infrastructure_retry:
    enabled: true
    max_attempts: 3
    initial_delay_seconds: 2
    max_delay_seconds: 60
```

## `archive`

Archive configuration.

| Key | Type | Default | Description |
|---|---|---|---|
| `export_method` | string | `app-store` | `app-store`, `ad-hoc`, `enterprise`, `development` |
| `include_symbols` | bool | `true` | Include dSYMs in archive |
| `include_bitcode` | bool | — | Include bitcode (deprecated in Xcode 14+) |
| `output_path` | string | — | Output path for `.xcarchive` |

## `export`

IPA export configuration.

| Key | Type | Description |
|---|---|---|
| `archive_path` | string | Path to the `.xcarchive` to export |
| `output_directory` | string | Directory for the exported IPA |

## `testflight`

TestFlight distribution settings.

| Key | Type | Default | Description |
|---|---|---|---|
| `skip_waiting_for_build_processing` | bool | `false` | Skip Apple's processing wait |
| `distribute_external` | bool | `false` | Distribute to external testers |
| `groups` | list | `[]` | Beta group names |
| `changelog` | string | — | Release notes for this build |

## `screenshots`

Screenshot capture settings.

| Key | Type | Default | Description |
|---|---|---|---|
| `devices` | list | `[]` | Simulator device names |
| `locales` | list | `[en-US]` | Locale identifiers |
| `scheme` | string | — | Xcode scheme for screenshot UI tests |
| `output_directory` | string | `./screenshots` | Output directory |

## `metadata`

App Store metadata settings.

| Key | Type | Default | Description |
|---|---|---|---|
| `directory` | string | `./metadata` | Local metadata directory |
| `submit_for_review` | bool | `false` | Submit for review after push |
| `automatic_release` | bool | `false` | Release automatically after approval |
| `phased_release` | bool | `false` | Use phased release |

## `versioning`

Version bump strategy.

| Key | Type | Default | Description |
|---|---|---|---|
| `strategy` | string | `sequential` | `sequential` or `timestamp` |
| `source` | string | `xcodeproj` | `xcodeproj`, `project_spec`, `kmp`, or `asc`. KMP reads/writes `versionName`/`versionCode` in `gradle.properties`. See <doc:KMPIntegration>. |

## `ios` / `android`

Per-platform overrides merged on top of the shared config when the resolved platform matches.

| Key | Type | Default | Description |
|---|---|---|---|
| `build_system` | string | `native` | Build system that produces the artifact: `native`, `flutter`, `react_native`, or `kmp`. Auto-detected from project files when unset. See ``BuildSystem`` and <doc:KMPIntegration>. |
| `scheme` / `workspace` / `project` (iOS) | string | — | Override `app.*` for iOS only. |
| `kmp_shared_module` (iOS) | string | `shared` | Gradle module containing KMP framework/test tasks. |
| `kmp_build_target` (iOS) | string | `IosSimulatorArm64` | KMP framework target used before local builds. |
| `kmp_archive_target` (iOS) | string | `IosArm64` | KMP framework target used before archives. |
| `kmp_test_task` (iOS) | string | `iosSimulatorArm64Test` | KMP Gradle task used for iOS-side Kotlin tests. |
| `module` / `build_variant` / `build_type` (Android) | string | varies | Override the Gradle module name and variant. |
| `test_scope` (Android) | string | `module` | Default test task scope: `module` or `root`. |
| `test_kind` (Android) | string | `unit` | Default test kind: `unit`, `instrumented`, or `e2e`. |
| `test_devices` (Android) | object | `{strategy: none}` | Default device config for instrumented tests. See below. |
| `gradlew_path` / `gradle_project_dir` (Android) | string | Shipfile directory | Controls local Gradle wrapper and working directory. |

```yaml
ios:
  build_system: kmp           # native (default) | flutter | react_native | kmp
  scheme: iosApp
  kmp_shared_module: shared
  kmp_build_target: IosSimulatorArm64
  kmp_archive_target: IosArm64
android:
  build_system: kmp
  module: androidApp
  gradle_project_dir: .
  test_scope: root
  test_kind: instrumented
  test_devices:
    strategy: named_emulators
    emulators:
      - Pixel_9_API_35
    prompt_locally: true
```

Flutter and React Native markers are reported by inspection, but runtime support is not active unless you explicitly set those values.

## `notifications`

Notification settings.

```yaml
notifications:
  slack:
    webhook_url: ${SLACK_WEBHOOK_URL}
    channel: "#releases"
    on_success: true
    on_failure: true
```

| Key | Type | Description |
|---|---|---|
| `webhook_url` | string | Incoming webhook URL |
| `channel` | string | Default channel |
| `on_success` | bool | Notify on success |
| `on_failure` | bool | Notify on failure |

## `workflows`

Named workflow definitions.

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
      options: { configuration: Release, export_method: app-store }
    - action: testflight
      options: { groups: ["Internal QA"] }
```

Each workflow is a list of steps. A step has:

| Key | Description |
|---|---|
| `action` | Registered action name |
| `options` | Optional key-value map passed to the action |

## Environment Variables

All config values can be set via `SHIPIT_*` environment variables. The mapping follows the YAML key path with dots replaced by underscores and prefixed with `SHIPIT_`:

| Env Var | Equivalent Shipfile Key |
|---|---|
| `SHIPIT_SCHEME` | `app.scheme` |
| `SHIPIT_BUNDLE_ID` | `app.bundle_id` |
| `SHIPIT_TEAM_ID` | `app.team_id` |
| `ASC_KEY_ID` | `app_store_connect.key_id` |
| `ASC_ISSUER_ID` | `app_store_connect.issuer_id` |
| `ASC_PRIVATE_KEY` | `app_store_connect.private_key` |
| `ASC_PRIVATE_KEY_PATH` | `app_store_connect.key_path` |
| `VAULT_PASSWORD` | Code signing vault passphrase |
| `SLACK_WEBHOOK_URL` | `notifications.slack.webhook_url` |

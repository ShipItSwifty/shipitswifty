# Configuration Reference

> **DocC mirror:** Also available as the `ConfigurationReference` article in the `ShipItKit` DocC archive.

All config file keys, environment variables, and CLI flags.

`Shipfile.yml` is only the default config filename. ShipIt reads `./Shipfile.yml` when `--shipfile` is omitted, but any YAML file path works with `--shipfile <path>`.

For config-backed CLI commands, the selected file must exist. A missing `./Shipfile.yml` or missing `--shipfile <path>` target causes the command to exit with code `2`.

## Priority Order

```
CLI flags  >  Shipfile.yml (config file)  >  SHIPIT_* env vars  >  .env file  >  Built-in defaults
```

`.env` values are loaded into the environment (see below), so they sit just under real `SHIPIT_*` env vars.

Relative filesystem paths are resolved against the directory containing the loaded Shipfile.
This applies to Xcode containers, build/export outputs, signing assets, version/project specs,
and Android Gradle or keystore paths. Absolute paths are preserved.

> **Secrets exception:** inline secrets prefer the environment over the config file. The raw ASC private key reads `ASC_PRIVATE_KEY` (env) **before** `app_store_connect.private_key` (Shipfile) so CI secrets win over anything committed. See the **Secrets bypass** note below.

### `.env` file auto-loading

ShipIt automatically loads a `.env` file from the same directory as `Shipfile.yml` before resolving configuration. Variables defined in `.env` are only set if not already present in the environment (real env vars always take precedence).

Supported formats:
- `KEY=VALUE`
- `export KEY=VALUE`
- Quoted values (`KEY="value"` or `KEY='value'`)
- Comments (`# ...`) and blank lines are ignored

Use `shipit generate` to create a `.env` file with signing credentials. The file is automatically added to `.gitignore`.

## Environment variable naming convention

Shipfile YAML keys map to env vars by upper-casing and joining path segments with `_`, prefixed with `SHIPIT_`. Nested keys use `__` (double-underscore) as the section separator.

| Shipfile key | Environment variable |
|---|---|
| `app.scheme` | `SHIPIT_APP__SCHEME` |
| `app.bundle_id` | `SHIPIT_APP__BUNDLE_ID` |
| `app.team_id` | `SHIPIT_APP__TEAM_ID` |
| `app_store_connect.key_id` | `SHIPIT_APP_STORE_CONNECT__KEY_ID` |
| `app_store_connect.issuer_id` | `SHIPIT_APP_STORE_CONNECT__ISSUER_ID` |
| `build.configuration` | `SHIPIT_BUILD__CONFIGURATION` |
| `archive.export_method` | `SHIPIT_ARCHIVE__EXPORT_METHOD` |
| `code_signing.git_url` | `SHIPIT_CODE_SIGNING__GIT_URL` |

**Secrets bypass:** `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `ASC_PRIVATE_KEY_PATH`, and `VAULT_PASSWORD` are also read directly (without the `SHIPIT_` prefix) for compatibility with standard CI secret naming.

## Top-Level Structure

```yaml
platform:
app:
app_store_connect:
code_signing:
build:
archive:
export:
testflight:
screenshots:
metadata:
versioning:
project_generation:
notifications:
workflows:
# Platform-specific overrides (merged on top of shared config)
ios:
android:
```

## `platform`

| Key | Type | Default | Description |
|---|---|---|---|
| `platform` | string | auto-detected | `ios` or `android`. When omitted, auto-detected from project files (`gradlew`/`build.gradle.kts` → android, `*.xcworkspace`/`*.xcodeproj` → ios). |

## `app`

| Key | Type | Description |
|---|---|---|
| `workspace` | string | Path to `.xcworkspace` |
| `project` | string | Path to `.xcodeproj` (used when `workspace` is nil) |
| `scheme` | string | Xcode scheme for build and test |
| `bundle_id` | string | App bundle identifier. Optional if it can be inferred from Xcode build settings |
| `team_id` | string | Apple Developer Team ID. Optional if it can be inferred from Xcode build settings |

Where to find these values manually:

- `bundle_id`: your target's bundle identifier in Xcode Signing settings or `PRODUCT_BUNDLE_IDENTIFIER` in build settings
- `team_id`: the 10-character Apple Developer Team ID for the team selected in Xcode Signing, also shown in the Apple Developer account / Certificates, IDs & Profiles

## `app_store_connect`

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

If ShipIt cannot infer `app.team_id`, use the team selected in Xcode for the app target. The value you need is the Apple Developer Team ID, not the App Store Connect issuer ID.

| Key | Type | Env Var | Description |
|---|---|---|---|
| `key_id` | string | `ASC_KEY_ID` | API key ID |
| `issuer_id` | string | `ASC_ISSUER_ID` | Issuer ID |
| `key_path` | string | — | Path to `.p8` key file |
| `private_key` | string | `ASC_PRIVATE_KEY` | Raw `.p8` contents |

## `code_signing`

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | string | `vault` | `automatic`, `vault`, or `manual` |
| `storage` | string | `git` | `git`, `s3`, or `gcs` |
| `git_url` | string | — | URL of the certificate repo |
| `app_identifier` | string | — | Bundle ID for matching |
| `profile_type` | string | — | `appstore`, `adhoc`, `development` |
| `p12_path` | string | — | Local `.p12` certificate path for manual signing |
| `p12_base64` | string | — | Base64-encoded `.p12` certificate for CI/manual signing |
| `p12_password` | string | — | `.p12` certificate password |
| `provisioning_profile_path` | string | — | Local `.mobileprovision` path for manual signing |
| `provisioning_profile_base64` | string | — | Base64-encoded `.mobileprovision` for CI/manual signing |

Set `VAULT_PASSWORD` env var for the encrypted repo passphrase.

With `type: automatic`, ShipIt passes `-allowProvisioningUpdates` to Xcode build/archive/export operations and writes `signingStyle=automatic` into export options. When App Store Connect API credentials (`ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY` / `ASC_PRIVATE_KEY_PATH`) are configured, ShipIt also passes `-authenticationKeyID`, `-authenticationKeyIssuerID`, and `-authenticationKeyPath` so automatic signing can authenticate to Apple's provisioning servers in headless CI where no Apple ID is signed in to Xcode. A raw `ASC_PRIVATE_KEY` is written to a temporary owner-only `.p8` file for the duration of the command.

With `type: manual`, `shipit sign sync` installs the configured `.p12` certificate and provisioning profile. Local paths are preferred when they exist; base64 values are used as a CI fallback.

## `build`

| Key | Type | Default | Description |
|---|---|---|---|
| `configuration` | string | `Release` | Build configuration |
| `derived_data_path` | string | — | Custom derived data path |
| `xcargs` | map | `{}` | Extra flags for `xcodebuild` |

## `archive`

| Key | Type | Default | Description |
|---|---|---|---|
| `export_method` | string | `app-store` | `app-store`, `ad-hoc`, `enterprise`, `development` |
| `include_symbols` | bool | `true` | Include dSYMs |
| `include_bitcode` | bool | — | Include bitcode (deprecated Xcode 14+) |
| `output_path` | string | — | Output path for `.xcarchive` |

## `export`

| Key | Type | Description |
|---|---|---|
| `archive_path` | string | Path to `.xcarchive` |
| `output_directory` | string | Output directory for IPA |

## `testflight`

| Key | Type | Default | Description |
|---|---|---|---|
| `skip_waiting_for_build_processing` | bool | `false` | Skip Apple's processing wait |
| `distribute_external` | bool | `false` | Distribute to external testers |
| `groups` | list | `[]` | Beta group names |
| `changelog` | string | — | Release notes |

## `screenshots`

| Key | Type | Default | Description |
|---|---|---|---|
| `devices` | list | `[]` | Simulator device names |
| `locales` | list | `[en-US]` | Locale identifiers |
| `scheme` | string | — | Screenshot UI test scheme |
| `output_directory` | string | `./screenshots` | Output directory |

## `metadata`

| Key | Type | Default | Description |
|---|---|---|---|
| `directory` | string | `./metadata` | Metadata directory |
| `submit_for_review` | bool | `false` | Submit for review |
| `automatic_release` | bool | `false` | Auto-release after approval |
| `phased_release` | bool | `false` | Phased release |

## `versioning`

ShipItSwifty follows Apple's two-version model:

| Plist key | Format | Meaning |
|---|---|---|
| `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH` | User-facing marketing version (e.g. `2.4.1`). Bumped manually for releases. |
| `CFBundleVersion` | plain integer | Internal build number (e.g. `317`). Auto-incremented on every beta run. |

The `versioning` section controls how `CFBundleVersion` is incremented. `CFBundleShortVersionString` is only changed when the `version` action is called with `bump: major`, `bump: minor`, or `bump: patch`.

| Key | Type | Default | Description |
|---|---|---|---|
| `strategy` | string | `sequential` | `sequential` — adds 1 each run (guarantees a plain integer). `timestamp` — uses `YYYYMMDDHHmm` format. |
| `source` | string | `xcodeproj` | `xcodeproj` — reads `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from `xcodebuild -showBuildSettings`; falls back to `agvtool`, then `plutil` on Info.plist. `asc` — reads current build number from App Store Connect; same fallback chain for the read phase. `project_spec` — reads/writes version values directly in a YAML spec file (XcodeGen/Tuist). `xcconfig` — reads/writes named keys directly in an `.xcconfig` file (set `spec_path` to the file and `marketing_key`/`build_key` to the variable names); use when the version lives in an `.xcconfig` referenced via `$(VAR)` from the project so the `$(VAR)` indirection is preserved. `kmp` — reads/writes `versionName`/`versionCode` in `gradle.properties`. `gradle` — reads/writes `versionName`/`versionCode` directly in `build.gradle.kts` or `build.gradle`; default for Android projects. `pubspec` — reads/writes the `version: X.Y.Z+B` key in `pubspec.yaml`; default for Flutter projects (`flutter build` stamps the native projects from it, so writing `xcodeproj`/`gradle` directly would be overwritten). |
| `spec_path` | string | — | Path to the version source file. Required when `source: project_spec` (e.g. `project.yml`) or `source: xcconfig` (e.g. `Config/Version.xcconfig`). For `source: pubspec`, defaults to `pubspec.yaml` at the project root. |
| `build_key` | string | — | Key for the build number in the spec file (YAML, e.g. `settings.CURRENT_PROJECT_VERSION`) or `.xcconfig` (e.g. `JOT_BUILD_NUMBER`). |
| `marketing_key` | string | — | Key for the marketing version in the spec file (YAML, e.g. `settings.MARKETING_VERSION`) or `.xcconfig` (e.g. `JOT_MARKETING_VERSION`). |

#### `source: xcconfig` example

For a project that keeps its version as a single source of truth in an `.xcconfig` file referenced
from the `.xcodeproj` via build-setting indirection:

```
// Config/Version.xcconfig
JOT_MARKETING_VERSION = 1.0.0
JOT_BUILD_NUMBER = 1
```
```
// project.pbxproj
MARKETING_VERSION = "$(JOT_MARKETING_VERSION)"
CURRENT_PROJECT_VERSION = "$(JOT_BUILD_NUMBER)"
```
```yaml
# Shipfile.yml
versioning:
  source: xcconfig
  spec_path: Config/Version.xcconfig
  marketing_key: JOT_MARKETING_VERSION
  build_key: JOT_BUILD_NUMBER
```

ShipIt rewrites only those two lines, leaving the `$(JOT_MARKETING_VERSION)` references in the
`.xcodeproj` intact. (The `xcodeproj` source would instead stamp literal values into the project's
build configurations, breaking the indirection — so prefer `xcconfig` for this layout.)

#### `source: pubspec` example (Flutter)

Flutter treats the pubspec `version:` key as the single source of truth — `flutter build` stamps
`CFBundleShortVersionString`/`CFBundleVersion` and `versionName`/`versionCode` from it on every
build, so bumping the native project files directly does not stick. `pubspec` is the default
source when the resolved build system is Flutter; the config below is only needed to override
the file location:

```yaml
# Shipfile.yml
versioning:
  source: pubspec            # default for build_system: flutter
  spec_path: pubspec.yaml    # optional; defaults to pubspec.yaml at the project root
```

The part before `+` is the marketing version, the part after is the build number
(`version: 1.2.3+45` → marketing `1.2.3`, build `45`). When the `+build` suffix is absent the
build number reads as `0`, so the first `bump: build` writes `+1`. Only the top-level
`version:` key is rewritten; comments and the rest of the file are preserved.

### `version` action options

The `version` action accepts a `bump` option that selects which counter to change:

| `bump` value | Changes | Leaves untouched |
|---|---|---|
| `build` | `CFBundleVersion` (integer) | `CFBundleShortVersionString` |
| `patch` | Patch segment of `CFBundleShortVersionString`; resets `CFBundleVersion` to `1` | Major and minor segments |
| `minor` | Minor segment; resets patch and `CFBundleVersion` to `1` | Major segment |
| `major` | Major segment; resets minor, patch, and `CFBundleVersion` to `1` | — |

### Version bump ordering and recovery

**Recommended order:** place `version` *after* steps that can fail (e.g. `test`, `archive`) and pair it with an immediate `git` commit step. This way a failed early step never touches version files, and a failed late step leaves the bump committed to git — recoverable with a plain `git revert`.

```yaml
workflows:
  beta:
    - action: test
    - action: archive
    - action: version          # bump only after build succeeds
      options: { bump: build }
    - action: git              # commit immediately so git is the rollback mechanism
      options:
        operation: commit      # stages all changes (git add -A) then commits
        commit_message: "chore: bump build number [skip ci]"
    - action: export
    - action: testflight
```

If a workflow fails after the bump but before the git commit, restore with:

```bash
git restore MyApp.xcodeproj/project.pbxproj   # xcodeproj source
# git restore project.yml                      # project_spec source
# git restore gradle.properties                # kmp source
```

**Preview before bumping:** use `--dry-run` to see the computed before/after values without writing anything:

```bash
swift run shipit version --bump build --dry-run
swift run shipit version --bump patch --dry-run --output json
```

### Beta workflow pattern (local-only, Apple semantics)

For a local beta that increments the build number, runs tests, then archives and exports:

```yaml
versioning:
  strategy: sequential   # CFBundleVersion stays a plain integer
  source: xcodeproj      # reads/writes MARKETING_VERSION + CURRENT_PROJECT_VERSION in .xcodeproj

workflows:
  beta:
    - action: version
      options:
        bump: build        # increments CFBundleVersion only; marketing version unchanged
    - action: test
      options:
        destinations:
          - "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"
        retry_on_failure: true   # retry each failing test once before surfacing a failure
        # only_testing:           # narrow to specific targets, e.g. [NovalingoTests/CoreTests]
        # skip_testing:           # skip slow targets, e.g. [NovalingoUITests]
    - action: archive
    - action: export       # exports IPA locally; no upload to App Store Connect
```

Use `xcodebuild -showdestinations -scheme <Scheme>` (or `shipit ai-session --goal local`) to
discover destination strings that are valid on your machine before filling in the `destinations` array.
You can list multiple destinations to run tests on several simulators or devices in one step.

**How `source: xcodeproj` is resolved:**

1. `xcodebuild -showBuildSettings` — reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` directly from Xcode build settings. This is the primary path for modern Xcode projects.
2. `xcrun agvtool` — fallback for projects that have `VERSIONING_SYSTEM = apple-generic` but not the newer `MARKETING_VERSION` key.
3. `plutil` on `Info.plist` — last resort for legacy projects.

To add a TestFlight upload later, append a `testflight` step and uncomment the `app_store_connect` section.

## `test` action options

The `test` action is configured inline in a workflow step. It does **not** have a top-level Shipfile section.

| Option | Type | Default | Description |
|---|---|---|---|
| `destinations` | list | — | **Required.** One or more xcodebuild destination strings. Each entry triggers a separate `xcodebuild test` pass; pass/fail/skip counts are aggregated. Discover valid values with `xcodebuild -showdestinations -scheme <Scheme>`. |
| `destination` | string | — | Legacy single-destination string. Promoted to a one-element `destinations` list internally. Prefer `destinations` for new configuration. |
| `scheme` | string | `app.scheme` | Xcode scheme containing the test targets. Falls back to `app.scheme` when omitted. |
| `configuration` | string | `Debug` | Build configuration used for test compilation. |
| `enable_code_coverage` | bool | — | Enable `-enableCodeCoverage YES`. When `true` and `result_bundle_path` is unset, a path of `./build/<scheme>-tests.xcresult` is auto-derived. |
| `result_bundle_path` | string | — | Output path for the `.xcresult` bundle. Auto-derived when `enable_code_coverage` is `true`. |
| `test_plan` | string | — | Named `.xctestplan` to run. |
| `only_testing` | list | — | Restrict to specific targets or test cases. Each entry maps to `-only-testing`. |
| `skip_testing` | list | — | Skip specific targets or test cases. Each entry maps to `-skip-testing`. |
| `retry_on_failure` | bool | `false` | Pass `-retry-tests-on-failure` to retry each failing test once. |
| `rerun_failed_tests` | object | — | Selectively rerun only the failed tests when the runner supports it. Supports `enabled` and `max_attempts` (default `2`). |
| `report_path` | string | — | Optional path to write the structured JSON `TestRunReport` for CI artifact upload. |
| `infrastructure_retry` | object | — | Retry the entire test invocation for transient infrastructure failures. Presence enables retries; omit to disable. Recommended default: `{ max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }`. |

`retry_on_failure`, `rerun_failed_tests`, and `infrastructure_retry` solve different problems. Use `retry_on_failure` for xcodebuild's built-in one-pass iOS retry behavior. Use `rerun_failed_tests` when you want ShipIt to collect the initial failures, rerun those specific tests once, and emit flaky/persistent failure information in `TestRunReport`. Use `infrastructure_retry` for whole-run failures such as simulator launch crashes, Android emulator disconnects, Flutter tool crashes, or JS worker failures.

`shipit generate` asks whether generated test steps should enable `infrastructure_retry`. `shipit ai-session` includes the same guidance in the agent prompt so AI-assisted workflow creation asks the same question.

## `test-results` action options

Use `test-results` to parse an existing `.xcresult` bundle or Gradle JUnit XML directory into a normalized JSON report.

| Option | Type | Default | Description |
|---|---|---|---|
| `format` | string | `text` | Output format hint: `text`, `json`, or `markdown`. |
| `platform` | string | resolved platform | Explicit platform override when parsing outside a Shipfile-backed context. |
| `xcresult_path` | string | auto-discover | Explicit path to a `.xcresult` bundle (iOS). Falls back to `./build/<scheme>-tests.xcresult` or the first `.xcresult` under `./build/`. |
| `report_path` | string | auto-discover | Explicit path to a JUnit XML report directory (Android). Falls back to common Gradle `build/test-results/...` locations. |
| `failed_only` | bool | `false` | Only include failed and errored tests in the parsed output. |
| `include_passed` | bool | `true` | Include passed tests in the parsed output. |
| `report_output_path` | string | — | Optional path to write the structured JSON report to disk. |

**Destination string format**

```
platform=iOS Simulator,name=<SimulatorName>,OS=<Version>
platform=iOS,name=<DeviceName>
platform=macOS
```

Run `xcodebuild -showdestinations -scheme <Scheme>` (with `-workspace` or `-project` as appropriate)
to list all valid destination strings for your scheme on the current machine. Alternatively, run
`shipit ai-session --goal local` which calls destination discovery automatically and includes the
results in `nextQuestion` so an AI agent can ask which destinations to use.

## `project_generation`

Configuration for automatic project file generation (XcodeGen, Tuist) before Xcode-dependent steps.

| Key | Type | Default | Description |
|---|---|---|---|
| `tool` | string | — | Generation tool to use: `xcodegen` or `tuist` |
| `command` | string | — | Custom shell command to run for generation (overrides `tool`) |
| `spec_path` | string | — | Path to the project spec file (e.g. `project.yml` for XcodeGen) |
| `output_project` | string | — | Expected output `.xcodeproj` path (used to verify generation succeeded) |
| `auto_generate` | bool | `true` | Automatically run generation before Xcode-dependent actions. Set to `false` to skip. |

## `notifications.slack`

| Key | Type | Description |
|---|---|---|
| `webhook_url` | string | Incoming webhook URL (use `${SLACK_WEBHOOK_URL}`) |
| `channel` | string | Default Slack channel |
| `on_success` | bool | Notify on success |
| `on_failure` | bool | Notify on failure |

## `workflows`

Workflows can be defined as a plain array of steps (legacy) or as an object with optional workflow-level overrides:

```yaml
# Legacy format: plain array of steps
workflows:
  beta:
    - action: archive
    - action: testflight

# New format: object with workflow-level overrides
workflows:
  release:
    build_variant: prodRelease
    steps:
      - action: archive
      - action: play-store
        options:
          track: production
```

### Workflow-level overrides

| Key | Type | Description |
|---|---|---|
| `build_variant` | string | Overrides `android.build_variant` for all steps in this workflow. Used by actions that auto-discover artifact paths (e.g. `play-store`, `validate bundle`). |
| `flavor` | string | Overrides `android.gradle_properties.flavor` for all steps in this workflow. Used for Flutter artifact path discovery. |
| `steps` | array | Required when using the object format. The ordered sequence of action steps. |

### Step fields

Each step:

| Key | Description |
|---|---|
| `action` | Registered action name |
| `options` | Optional key-value map passed to the action |

Use these AI-oriented commands to inspect the supported workflow surface:

```bash
swift run shipit ai-session --goal beta
swift run shipit schema --output json
swift run shipit inspect project --output json
swift run shipit generate --goal beta
swift run shipit validate yml --shipfile ./Shipfile.yml --output json
```

`ai-session` always emits JSON and is intended for AI/tooling integrations rather than direct human consumption.

Workflow notes:

- `export` can write an IPA into `export.output_directory`.
- `testflight` and `upload` can reuse that exported IPA automatically when they run after `export` in the same workflow and no explicit `ipa` / `ipa_path` is set.
- `validate` reports an error when `testflight` or `upload` has no explicit IPA and no prior export context.

## `custom_actions`

User-defined composite actions — reusable, parameterized sequences of built-in actions (or other custom actions). Use these to avoid duplicating step blocks across workflows (for example sharing `test → archive → export` between `beta` and `adhoc`).

```yaml
custom_actions:
  <composite-name>:
    description: "Human-readable summary (optional)."
    parameters:
      <param-name>:
        type: string        # string | bool | int | number | array | object | any
        required: true       # defaults to true when no default is set
        default: <value>     # optional fallback when call site omits the value
        description: "..."
    steps:
      - action: <registered-action-or-other-composite>
        options:
          <option>: "{{param.<param-name>}}"
```

Invocation is identical to a built-in action — a workflow step uses `action: <composite-name>` and forwards call-site values via its `options:` block:

```yaml
custom_actions:
  build_and_sign:
    description: "Test, archive, and export the app with a chosen export method."
    parameters:
      method:
        type: string
        required: true
    steps:
      - action: test
      - action: archive
      - action: export
        options:
          method: "{{param.method}}"

workflows:
  beta:
    - action: build_and_sign
      options:
        method: app-store
    - action: testflight
  adhoc:
    - action: build_and_sign
      options:
        method: ad-hoc
    - action: notify
```

### Parameter reference syntax: `{{param.NAME}}`

Inside a step's `options:` block, string values may reference declared parameters using `{{param.NAME}}`. This delimiter is chosen to stay out of the way of every common template system that surrounds a Shipfile:

| System | Template syntax | Safe alongside `{{param.X}}`? |
|---|---|---|
| Shipfile `${ENV_VAR}` expansion | `${FOO}` | ✅ Different delimiter. Env expansion runs *before* composite substitution, so you can freely mix: `key: "{{param.track}}-${DEPLOY_ENV}"`. |
| GitHub Actions | `${{ env.X }}`, `${{ secrets.X }}` | ✅ Different delimiter (leading `$` + double braces). |
| CircleCI parameters | `<< parameters.X >>` | ✅ Different delimiter. |
| Xcode Cloud / shell | `$VAR`, `${VAR}` | ✅ Different delimiter. |

Rules:

- Only string **leaves** in a step's `options:` are scanned. Keys and non-string scalars are untouched.
- When a string is *exactly* `{{param.NAME}}`, the underlying typed JSON value is substituted (`bool`, `int`, `array`, `object`). When it appears inline with other text, the value is stringified.
- Unknown parameter references cause `shipit validate yml` to report an error rather than silently expanding to an empty string.

### Validation rules

`shipit validate yml` enforces:

- Custom action names must not collide with built-in action names.
- `steps:` must contain at least one step.
- Each step's `action:` must resolve to a built-in or another declared custom action.
- Each `{{param.NAME}}` reference inside a step's options must match a declared parameter.
- Required parameters must be supplied at the call site (or have a `default:`).
- The graph of composite-to-composite references must be acyclic.

### AI-session integration

`shipit ai-session` includes the user's custom actions in the generated agent prompt (name, description, and declared parameters). Agents are instructed to prefer invoking an existing composite over duplicating its step sequence in a new workflow.

## Workflow tokens & step conditions

Top-level workflow steps support reserved interpolation tokens and an optional `when:` condition. These let a workflow tag the version it just released without external shell/`jq` glue — the whole release runs as one `shipit run release`.

### Reserved tokens

| Token | Resolves to |
|---|---|
| `{{version}}` | The marketing version (e.g. `1.2.3`), from a prior `version` step or the current versioning source. |
| `{{build_number}}` | The build number (e.g. `42`). |
| `{{version_changed}}` | `true`/`false` — whether the marketing version string changed (`false` for a build-only bump). |

Rules:

- Tokens are substituted into string leaves of a step's `options:` **and** into its `when:` value, at run time.
- Values come from the most recent `version` step's result. Before any `version` step runs they are seeded best-effort from the current versioning source (and `{{version_changed}}` is `false`).
- An unknown or not-yet-resolved token is left **literal** (and logged) rather than expanding to empty.
- These are **distinct** from composite `{{param.NAME}}` references and from Shipfile `${ENV_VAR}` expansion. Resolution is scoped to top-level workflow steps; tokens inside `custom_actions` substeps are not resolved in this release.

### `when:` conditions

A step may carry `when: "<expr>"`. Reserved tokens are substituted first, then the result is evaluated for truthiness: `true`, `1`, or `yes` (case-insensitive) run the step; anything else — including an unresolved literal token — **skips** it (recorded with status `skipped`; the workflow continues). v1 supports a single truthy token, not operators or comparisons.

### Example: tag the released version

```yaml
workflows:
  release:
    - action: version
      options: { bump: patch }        # or { bump: ${RELEASE_BUMP} } to drive from CI
    - action: archive
    - action: play-store
      options: { track: production }
    - action: git
      options: { operation: commit, commit_message: "chore: release v{{version}} (build {{build_number}})" }
    - action: git
      when: "{{version_changed}}"      # skipped on build-only bumps
      options: { operation: tag, tag_name: "v{{version}}" }
    - action: git
      options: { operation: push, push_tags: true }
```

`shipit generate --goal release` scaffolds this workflow (including the git commit/tag/push tail) for both iOS and Android.

## Environment Variables Summary

| Variable | Maps To |
|---|---|
| `ASC_KEY_ID` | `app_store_connect.key_id` |
| `ASC_ISSUER_ID` | `app_store_connect.issuer_id` |
| `ASC_PRIVATE_KEY` | `app_store_connect.private_key` |
| `ASC_PRIVATE_KEY_PATH` | `app_store_connect.key_path` |
| `VAULT_PASSWORD` | Code signing passphrase |
| `SLACK_WEBHOOK_URL` | `notifications.slack.webhook_url` |
| `SHIPIT_APP__SCHEME` | `app.scheme` |
| `SHIPIT_APP__BUNDLE_ID` | `app.bundle_id` |
| `SHIPIT_APP__TEAM_ID` | `app.team_id` |

## `android`

Platform-specific Android configuration. These values are merged on top of shared config when `--platform android` is active or the platform is auto-detected as Android.

| Key | Type | Default | Env Var | Description |
|---|---|---|---|---|
| `build_system` | string | `native` | `SHIPIT_ANDROID__BUILD_SYSTEM` | Build system that produces the Android artifact. One of `native`, `flutter`, `react_native`, `kmp`. See [Build systems](#build-systems). |
| `module` | string | `app` | — | Gradle module to build/bundle |
| `build_variant` | string | `release` | — | Gradle build variant (e.g. `release`, `debug`) |
| `build_type` | string | `aab` | — | `aab` (Android App Bundle) or `apk` |
| `package_name` | string | — | `SHIPIT_ANDROID__PACKAGE_NAME` | Android application ID (e.g. `com.example.app`) |
| `keystore_path` | string | — | — | Path to the release keystore |
| `keystore_password` | string | — | `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `keystore_alias` | string | — | `ANDROID_KEY_ALIAS` | Key alias in the keystore |
| `key_password` | string | — | `ANDROID_KEY_PASSWORD` | Key password |
| `rollout_fraction` | float | — | — | Staged rollout fraction (0.0–1.0), for `production` track |
| `gradle_properties` | map | `{}` | — | Extra `-P key=value` properties passed to Gradle |
| `gradlew_path` | string | — | `SHIPIT_ANDROID__GRADLEW_PATH` | Explicit path to the `gradlew` script (auto-detected when omitted) |
| `gradle_project_dir` | string | Shipfile directory | `SHIPIT_ANDROID__GRADLE_PROJECT_DIR` | Directory containing the Gradle root project |
| `gradle_flags` | array | `[]` | — | Extra Gradle flags such as `--configuration-cache` or `--stacktrace` |

### Google Play credentials

Set these environment variables for Google Play upload actions:

| Variable | Description |
|---|---|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Full JSON content of the service account key file |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Path to the service account key JSON file |

Lookup notes:

- `package_name` is your Android `applicationId`, usually from `app/build.gradle` or `app/build.gradle.kts`
- Create the service account in Google Cloud, enable the `Google Play Developer API`, then invite that service account in Play Console `Users and permissions`
- Give the service account Play Console permissions that match the rollout you want to perform

> **Env var naming:** Android keystore variables support both the short form (`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`) and the standard `SHIPIT_` prefix form (`SHIPIT_ANDROID__KEYSTORE_PASSWORD`, `SHIPIT_ANDROID__KEY_PASSWORD`, `SHIPIT_ANDROID__KEY_ALIAS`). The short forms are checked as a compatibility fallback when the `SHIPIT_`-prefixed forms are not set.

## `ios`

Platform-specific iOS overrides. Merged on top of shared config when `--platform ios` is active. All top-level `app`, `code_signing`, `archive`, `export`, `testflight`, and `screenshots` keys can appear here to override the shared defaults for iOS only.

| Key | Type | Default | Env Var | Description |
|---|---|---|---|---|
| `build_system` | string | `native` | `SHIPIT_IOS__BUILD_SYSTEM` | Build system that produces the iOS artifact. One of `native`, `flutter`, `react_native`, `kmp`. See [Build systems](#build-systems). |
| `kmp_shared_module` | string | `shared` | `SHIPIT_IOS__KMP_SHARED_MODULE` | Gradle module containing KMP framework/test tasks |
| `kmp_build_target` | string | `IosSimulatorArm64` | `SHIPIT_IOS__KMP_BUILD_TARGET` | KMP target linked before local `xcodebuild build` |
| `kmp_archive_target` | string | `IosArm64` | `SHIPIT_IOS__KMP_ARCHIVE_TARGET` | KMP target linked before `xcodebuild archive` |
| `kmp_test_task` | string | `iosSimulatorArm64Test` | `SHIPIT_IOS__KMP_TEST_TASK` | KMP Gradle task used by `shipit test --platform ios` |
| `scheme` | string | — | `SHIPIT_IOS__SCHEME` | iOS-specific Xcode scheme override |
| `workspace` | string | — | `SHIPIT_IOS__WORKSPACE` | iOS-specific Xcode workspace override |
| `project` | string | — | `SHIPIT_IOS__PROJECT` | iOS-specific Xcode project override |

```yaml
ios:
  build_system: native      # native (default) | flutter | react_native | kmp
  scheme: MyApp
archive:
  export_method: app-store
```

## Build systems

`build_system` is **orthogonal** to `platform`: a single Kotlin Multiplatform or Flutter source tree can produce both an iOS `.ipa` and an Android `.aab`. Setting `build_system` tells ShipItSwifty *how* the native artifact is compiled before the regular distribution pipeline (sign / archive / export / TestFlight / Play Store) runs.

| Value | Compilation step (iOS) | Compilation step (Android) | Available |
|---|---|---|---|
| `native` (default) | `xcodebuild` | `gradlew assemble` / `bundle` | ✅ Always |
| `kmp` | build: `:<shared>:link…IosSimulatorArm64` → `xcodebuild`; archive: `:<shared>:link…IosArm64` → `xcodebuild archive` | `gradlew :androidApp:assembleRelease` / `:androidApp:bundleRelease` | ✅ This release |
| `flutter` | `flutter build ipa` (IPA at `build/ios/ipa/`; no export step) | build: `flutter build apk`; archive: `flutter build appbundle` → `build/app/outputs/bundle/release/app-release.aab` | ✅ This release |
| `react_native` | Metro bundle → `xcodebuild archive` + export | build: `npx react-native build-android --mode=release`; archive: `npx react-native build-android --mode=release --tasks bundleRelease` → `android/app/build/outputs/bundle/release/app-release.aab` | ✅ This release |

### Auto-detection

When `build_system` is unset, ShipItSwifty inspects the project root and resolves it automatically:

| Project marker | Detected value |
|---|---|
| `pubspec.yaml` containing a `flutter:` key | `flutter` — activates Flutter runtime build paths |
| `package.json` declaring `react-native` in `dependencies` or `devDependencies` | `react_native` — activates RN runtime build paths |
| `build.gradle.kts` applying `kotlin("multiplatform")` or `org.jetbrains.kotlin.multiplatform` | `kmp` |
| none of the above | `native` |

You can override the resolved value via `--platform` plus the `SHIPIT_IOS__BUILD_SYSTEM` / `SHIPIT_ANDROID__BUILD_SYSTEM` environment variables, or by setting `build_system:` explicitly under the relevant Shipfile block.

### KMP example

```yaml
ios:
  build_system: kmp
  scheme: iosApp
  workspace: iosApp/iosApp.xcworkspace
  kmp_shared_module: shared
  kmp_build_target: IosSimulatorArm64
  kmp_archive_target: IosArm64
android:
  build_system: kmp
  module: androidApp
  gradle_project_dir: .
versioning:
  source: kmp           # reads/writes versionName + versionCode in gradle.properties
  spec_path: gradle.properties
```

The KMP iOS path links the configured shared framework target via Gradle before invoking `xcodebuild`, so the Xcode wrapper can resolve the framework import. The Android path is identical to a regular module-qualified Android Gradle build.

## `coverage` action options

The `coverage` action reads native coverage artifacts — it does not generate them. Configure it inline in workflow steps or use as a standalone command.

| Option | Type | Default | Description |
|---|---|---|---|
| `platform` | string | auto-detected | `ios` or `android` |
| `xcresult` | string | auto-discovered | Explicit `.xcresult` bundle path (iOS) |
| `report` | string | auto-discovered | Explicit JaCoCo XML report path (Android) |
| `first_party_only` | bool | `true` | Suppress test bundles, SPM deps, and known vendor prefixes |
| `targets` | bool | `false` | Show per-target/module breakdown |
| `files` | bool | `false` | Show per-file breakdown |
| `include_target` | list | `[]` | Include only these targets (overrides first-party filter) |
| `exclude_target` | list | `[]` | Exclude specific targets |
| `sort` | string | `coverage` | `coverage` (lowest first) or `name` |
| `limit` | int | — | Cap number of entries shown |
| `format` | string | `text` | `text`, `json`, or `markdown` |

## Linux and Docker support

Android actions (build, test, archive, lint, play-store, validate bundle) and all config resolution run natively on Linux. iOS-specific actions (`xcodebuild`-backed, code signing, TestFlight, etc.) are gated behind `#if os(macOS)`.

Use the Makefile targets for Docker-based development and CI:

| Target | Description |
|---|---|
| `make build-linux` | Build via direct volume mount |
| `make test-linux` | Run Linux-compatible tests |
| `make test-linux-coverage` | Tests + `--enable-code-coverage` |
| `make shell-linux` | Interactive container shell |
| `make docker-build` | Build local image (caches SPM deps as a layer) |
| `make docker-test` | Run tests inside local image |

## `shipit generate` — guided setup

`shipit generate --goal <local|beta|release>` is the recommended first command. It:

1. Inspects the project directory for Xcode workspaces/projects, `gradlew`, `pubspec.yaml`, etc.
2. Auto-detects platform, scheme, bundle ID, team ID, and build system.
3. Prompts interactively for missing or ambiguous values.
4. Writes `Shipfile.yml` with comments and env var references.
5. For Android signing, guides keystore discovery and offers three persistence options:
   - **`.env` file** (recommended for local dev) — uses `${VAR_NAME}` references for values already in env, inlines only user-provided values. Auto-adds `.env` to `.gitignore`.
   - **Shell profile** (`~/.zshrc` or `~/.bashrc`) — appends `export` lines.
   - **Manual** — prints the required export lines for you to handle.
6. Runs `shipit doctor` to validate the environment.

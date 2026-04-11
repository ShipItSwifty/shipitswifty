# Configuration Reference

All config file keys, environment variables, and CLI flags.

`Shipfile.yml` is only the default config filename. ShipIt reads `./Shipfile.yml` when `--shipfile` is omitted, but any YAML file path works with `--shipfile <path>`.

For config-backed CLI commands, the selected file must exist. A missing `./Shipfile.yml` or missing `--shipfile <path>` target causes the command to exit with code `2`.

## Priority Order

```
CLI flags  >  SHIPIT_* env vars  >  config file  >  Built-in defaults
```

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
notifications:
workflows:
```

## `app`

| Key | Type | Description |
|---|---|---|
| `workspace` | string | Path to `.xcworkspace` |
| `project` | string | Path to `.xcodeproj` (used when `workspace` is nil) |
| `scheme` | string | Xcode scheme for build and test |
| `bundle_id` | string | App bundle identifier. Optional if it can be inferred from Xcode build settings |
| `team_id` | string | Apple Developer Team ID. Optional if it can be inferred from Xcode build settings |

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

Set `VAULT_PASSWORD` env var for the encrypted repo passphrase.

With `type: automatic`, ShipIt passes `-allowProvisioningUpdates` to Xcode build/export operations and writes `signingStyle=automatic` into export options.

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
| `source` | string | `xcodeproj` | `xcodeproj` — reads `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from `xcodebuild -showBuildSettings`; falls back to `agvtool`, then `plutil` on Info.plist. `asc` — reads current build number from App Store Connect; same fallback chain for the read phase. |

### `version` action options

The `version` action accepts a `bump` option that selects which counter to change:

| `bump` value | Changes | Leaves untouched |
|---|---|---|
| `build` | `CFBundleVersion` (integer) | `CFBundleShortVersionString` |
| `patch` | Patch segment of `CFBundleShortVersionString`; resets `CFBundleVersion` to `1` | Major and minor segments |
| `minor` | Minor segment; resets patch and `CFBundleVersion` to `1` | Major segment |
| `major` | Major segment; resets minor, patch, and `CFBundleVersion` to `1` | — |

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

## `notifications.slack`

| Key | Type | Description |
|---|---|---|
| `webhook_url` | string | Incoming webhook URL (use `${SLACK_WEBHOOK_URL}`) |
| `channel` | string | Default Slack channel |
| `on_success` | bool | Notify on success |
| `on_failure` | bool | Notify on failure |

## `workflows`

```yaml
workflows:
  <workflow-name>:
    - action: <action-name>
      options:
        key: value
```

Each step:

| Key | Description |
|---|---|
| `action` | Registered action name |
| `options` | Optional key-value map passed to the action |

Use these AI-oriented commands to inspect the supported workflow surface:

```bash
swift run shipit ai-bootstrap --goal beta
swift run shipit schema --output json
swift run shipit inspect project --output json
swift run shipit suggest-config --goal beta --output json
swift run shipit validate yml --shipfile ./Shipfile.yml --output json
```

`ai-bootstrap` always emits JSON and is intended for AI/tooling integrations rather than direct human consumption.

Workflow notes:

- `export` can write an IPA into `export.output_directory`.
- `testflight` and `upload` can reuse that exported IPA automatically when they run after `export` in the same workflow and no explicit `ipa` / `ipa_path` is set.
- `validate` reports an error when `testflight` or `upload` has no explicit IPA and no prior export context.

## Environment Variables Summary

| Variable | Maps To |
|---|---|
| `ASC_KEY_ID` | `app_store_connect.key_id` |
| `ASC_ISSUER_ID` | `app_store_connect.issuer_id` |
| `ASC_PRIVATE_KEY` | `app_store_connect.private_key` |
| `ASC_PRIVATE_KEY_PATH` | `app_store_connect.key_path` |
| `VAULT_PASSWORD` | Code signing passphrase |
| `SLACK_WEBHOOK_URL` | `notifications.slack.webhook_url` |
| `SHIPIT_SCHEME` | `app.scheme` |
| `SHIPIT_BUNDLE_ID` | `app.bundle_id` |
| `SHIPIT_TEAM_ID` | `app.team_id` |

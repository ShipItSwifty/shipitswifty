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

| Key | Type | Default | Description |
|---|---|---|---|
| `strategy` | string | `sequential` | `sequential` or `timestamp` |
| `source` | string | `xcodeproj` | `xcodeproj` or `asc` |

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

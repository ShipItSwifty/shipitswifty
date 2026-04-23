# Validation

Catch problems before they reach App Store Connect or Google Play.

## Overview

The `validate` command family runs static checks against your configuration, metadata, and built artifacts, surfacing problems that would otherwise only appear after a long upload. Every validator returns a ``ActionResultEnvelope`` with structured issue lists, suitable for CI gating and AI agent consumption.

## The validators

| Subcommand | Validates | Backed by |
|---|---|---|
| `validate yml` | Shipfile structure + workflow semantics | ``ShipfileValidator`` |
| `validate metadata` | Localized App Store metadata against Apple guidelines | ``PrecheckAction`` |
| `validate archive` | `.xcarchive` / `.ipa` ready for App Store upload | ``ValidateArchiveAction`` |
| `validate bundle` | `.aab` / APK ready for Google Play upload | ``ValidateBundleAction`` |
| `validate all` | yml + metadata + archive in sequence | composition |
| `precheck` | Backwards-compat alias for `validate metadata` | — |

## `validate yml`

The fastest, cheapest check — runs entirely in-process and surfaces:

- Unknown top-level keys.
- Workflow steps referencing actions that aren't registered.
- Composite actions that:
  - Collide with built-in names.
  - Reference undeclared parameters in `{{param.NAME}}`.
  - Form a cycle (`a → b → a`).
- Required Shipfile fields that are present but blank.

```bash
shipit validate yml
shipit validate yml --output json | jq '.payload.issues'
```

## `validate metadata`

Runs Apple's same metadata rules against your local `metadata/` tree before you push it. Catches:

- Strings exceeding length limits per locale.
- Invalid characters in keywords.
- Missing required localizations.
- Banned terms.

```bash
shipit validate metadata
shipit precheck            # backwards-compat alias
```

## `validate archive`

Static validation of a built `.xcarchive` or exported `.ipa`:

- Bundle ID consistency.
- Version / build number sanity.
- Required Info.plist keys present.
- Embedded provisioning profile matches the export method.
- dSYMs present when expected.

```bash
shipit validate archive --archive-path ./build/MyApp.xcarchive
shipit validate archive --ipa ./build/export/MyApp.ipa
```

## `validate bundle`

Static validation of an Android `.aab` or APK:

- Manifest packageName matches the configured `package_name`.
- versionCode is monotonically increasing.
- Required permissions and `applicationId` look correct.
- Signing block present (when expected).

```bash
shipit validate bundle --bundle ./build/app-release.aab
shipit validate bundle --apk ./build/app-release.apk
```

## `validate all`

Runs the full sequence — `yml` → `metadata` → `archive` (iOS) — and aggregates results into a single envelope. Useful as a single CI gate.

```bash
shipit validate all
shipit validate all --output json
```

## CI gating pattern

```bash
# Fail the PR if anything is wrong.
shipit validate yml --output json | jq -e '.status == "success"'
shipit validate metadata --output json | jq -e '.status == "success"'
```

For Android pipelines:

```bash
shipit validate yml
shipit validate bundle --bundle ./app/build/outputs/bundle/release/app-release.aab
```

## See also

- ``ShipfileValidator``
- ``PrecheckAction``
- ``ValidateArchiveAction``
- ``ValidateBundleAction``
- <doc:CIIntegration>
- <doc:OutputFormats>

# Error Handling

Every failure is a typed ``ShipItError`` with a documented exit code.

## Overview

ShipItKit uses a single error enum, ``ShipItError``, for every failure surface. Each case carries the structured context the caller needs to diagnose the problem (exit codes, log excerpts, validation issue lists), and each case maps to a stable CLI exit code so CI gates can be written without parsing log strings.

## Exit-code table

| Exit | Cases | Domain |
|---|---|---|
| **2** | `invalidConfiguration`, `duplicateAction`, `missingTool` | Configuration / general |
| **10** | `buildFailed` | Build |
| **11** | `testFailed` | Test |
| **12** | `archiveFailed` | Archive / export |
| **20** | `signingResourceNotFound`, `keychainError` | Code signing |
| **30** | `apiError`, `jwtGenerationFailed`, `uploadFailed` | App Store Connect / Google Play |
| **40** | `screenshotCaptureFailed` | Screenshots |
| **50** | `precheckFailed`, `validateArchiveFailed` | Metadata / archive validation |

The table is also exposed at runtime via ``ShipItError/exitCode``.

## Catching in Swift

```swift
do {
    let result = try await BuildAction().run(with: options, context: context)
    print("✅ \(result.appPath ?? "?")")
} catch let error as ShipItError {
    context.logger.error("Build failed (exit \(error.exitCode)): \(error.localizedDescription)")
    throw ExitCode(error.exitCode)
}
```

Every `ShipItError` conforms to `LocalizedError`, so `error.localizedDescription` produces a human-readable string suitable for logs.

## Pattern-matching cases

```swift
do {
    try await action.run(with: opts, context: context)
} catch ShipItError.apiError(let status, let body) where status == 429 {
    // Rate-limited; back off and retry.
} catch ShipItError.precheckFailed(let violations) {
    // Show every violation to the user.
    for v in violations { print("• \(v)") }
} catch ShipItError.invalidConfiguration(let reason) {
    print("Fix Shipfile: \(reason)")
}
```

## CLI behaviour

The CLI catches every thrown `ShipItError` at the top level and:

1. Renders the error appropriately for `--output human` or `--output json`.
2. Exits with `error.exitCode`.

In JSON mode the failure envelope looks like:

```json
{
  "action": "build",
  "status": "failure",
  "payload": {
    "error": "buildFailed",
    "exitCode": 10,
    "message": "Build failed with exit code 65.\n…",
    "log": "…truncated…"
  }
}
```

## Common failures and fixes

| Error | Likely cause | Fix |
|---|---|---|
| `invalidConfiguration: app.scheme is required` | No scheme in Shipfile and none on CLI | Add `app.scheme` or pass `--scheme` |
| `missingTool: xcodebuild` | Xcode CLT not selected | `sudo xcode-select -s /Applications/Xcode.app` |
| `missingTool: gradlew` | Android project missing wrapper | `gradle wrapper` once at the project root |
| `signingResourceNotFound: profile` | Wrong `profile_type` for export method | Match `profile_type` to `export_method` |
| `apiError(401)` | Bad ASC key, expired token, wrong issuer ID | Re-check `ASC_*` env vars; `issuer_id` is **not** in the `.p8` |
| `apiError(403)` | API key lacks the required scope | Re-create the key with the correct role |
| `apiError(429)` | Rate-limited by Apple | ShipItKit retries automatically; if persistent, slow your CI |
| `uploadFailed` | Network blip mid-chunk | Re-run; ``RetryPolicy`` will back off |
| `precheckFailed` | App Store guideline violation in metadata | Read the `violations` list, fix the strings, re-run `validate metadata` |
| `validateArchiveFailed` | Archive missing dSYMs / wrong profile | Re-archive after fixing the underlying setting |
| `duplicateAction` | Plugin registered an existing built-in name | Rename the plugin's action |

## Retries

For transient failures (HTTP 429, network glitches, asset chunk uploads), wrap the throwing call in a ``RetryPolicy``:

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: .seconds(1), multiplier: 2.0)
let result = try await policy.execute {
    try await context.appStoreConnect.get("/v1/apps") as ASCListResponse<App>
}
```

``AppStoreConnectClient`` already wraps its own calls in a retry policy — you only need this when composing higher-level flows.

## CI gating

Because exit codes are stable, CI gates can be written without parsing JSON:

```bash
shipit run beta --ci
case $? in
  0)  echo "Beta released." ;;
  10) echo "::error::Build failed."; exit 1 ;;
  20) echo "::error::Code signing problem — check vault."; exit 1 ;;
  30) echo "::error::Apple API problem — check ASC creds."; exit 1 ;;
  *)  echo "::error::Unknown failure ($?)"; exit 1 ;;
esac
```

## See also

- ``ShipItError``
- ``RetryPolicy``
- ``ActionResultEnvelope``
- <doc:OutputFormats>
- <doc:CIIntegration>

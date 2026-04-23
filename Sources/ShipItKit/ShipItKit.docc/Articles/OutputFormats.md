# Output Formats

Human-readable terminal output and stable, machine-readable JSON — under the same flags everywhere.

## Overview

Every `shipit` subcommand and every action returns the same logical thing: an ``ActionResultEnvelope``. The output **format** is decided at the CLI boundary by `--output` and `--color`. JSON output is stable and never coloured; human output is friendly and may be coloured depending on `--color`.

## The envelope

```swift
public struct ActionResultEnvelope: Codable, Sendable {
    public let action: String         // e.g. "build", "run", "coverage"
    public let status: String         // "success" | "failure" | "dry_run"
    public let payload: JSONValue?    // typed result, encoded as JSON
}
```

Encoded:

```json
{
  "action": "build",
  "status": "success",
  "payload": {
    "appPath": "/Users/me/Library/.../MyApp.app",
    "exitCode": 0,
    "warnings": 0
  }
}
```

The `payload` is the action's typed `Result` — see each action's reference page for its shape.

## Format flags

| Flag | Default | Effect |
|---|---|---|
| `--output human` | yes | Pretty-printed terminal output, optionally coloured |
| `--output json`  | — | Stable JSON envelope, never coloured |
| `--color auto`   | yes | Colour iff stdout is a TTY |
| `--color always` | — | Force colour (useful for piped logs you'll read in a viewer) |
| `--color never`  | — | Suppress colour |
| `--no-color`     | — | Alias for `--color never` |

JSON output **never** contains ANSI colour codes regardless of `--color`.

## Streaming behaviour

- Human output streams line-by-line as actions progress.
- JSON output is **buffered**: a single envelope is printed on completion (success or failure). This keeps the JSON valid for parsers like `jq`.
- For per-step progress in JSON, set `--verbose` to emit incremental envelopes.

## Workflow output

A workflow's envelope wraps an array of step envelopes:

```json
{
  "action": "run",
  "status": "success",
  "payload": {
    "workflow": "beta",
    "stepCount": 3,
    "results": [
      { "action": "version",    "status": "success", "payload": { "buildNumber": 412 } },
      { "action": "archive",    "status": "success", "payload": { "archivePath": "..." } },
      { "action": "testflight", "status": "success", "payload": { "buildId": "abc-123" } }
    ]
  }
}
```

## Dry-run output

Dry-run runs don't actually execute the actions — they emit the resolved plan instead:

```json
{
  "action": "run",
  "status": "dry_run",
  "payload": {
    "workflow": "release",
    "mode": "dry_run",
    "stepCount": 4,
    "steps": [
      { "index": 1, "action": "version", "options": { "bump": "build" } },
      { "index": 2, "action": "archive", "options": null },
      { "index": 3, "action": "export",  "options": null },
      { "index": 4, "action": "upload",  "options": { "submit_for_review": true } }
    ]
  }
}
```

## Failure envelopes

On failure, the envelope's `status` is `"failure"` and the `payload` includes a typed error description:

```json
{
  "action": "build",
  "status": "failure",
  "payload": {
    "error": "buildFailed",
    "exitCode": 65,
    "log": "...truncated stderr..."
  }
}
```

The CLI **also** exits with the documented non-zero exit code (see <doc:ErrorHandling>). JSON consumers should rely on the exit code as the primary signal and the payload for diagnostic detail.

## `jq` recipes

```bash
# Did it succeed?
shipit run beta --output json | jq -e '.status == "success"'

# Pull a single field
shipit build --output json | jq -r '.payload.appPath'

# Coverage gate
shipit coverage --format json --summary \
  | jq -e '.payload.overallLineCoverage > 75'

# Show failed step in a workflow
shipit run release --output json \
  | jq '.payload.results[] | select(.status == "failure")'
```

## Programmatic encoding

If you embed ShipItKit in a Swift tool, ``JSONReporter`` produces the exact same JSON the CLI emits:

```swift
let reporter = JSONReporter()                     // pretty-printed by default
let json = try reporter.encode(envelope)
print(json)
```

For arbitrary `Encodable` payloads (e.g. an ``AISessionPayload``), use ``JSONReporter/encodeAny(_:)``.

## See also

- ``ActionResultEnvelope``
- ``JSONReporter``
- ``JSONValue``
- <doc:ErrorHandling>
- <doc:CIIntegration>

# AI Session

A stable, versioned JSON contract that lets AI agents drive ShipItSwifty setup and execution.

## Overview

`shipit ai-session` is the canonical machine-oriented entrypoint to ShipItSwifty. It runs ``ProjectInspector`` against the current directory, infers as much config as possible, identifies what's missing, and returns a versioned JSON payload that an AI agent can act on without ever calling another sub-command first.

The shape of that payload is defined by ``AISessionPayload`` and produced by ``AISessionBuilder``. The contract version is exposed at ``AISessionBuilder/contractVersion`` and changes only on breaking shape changes.

## Why a structured contract?

Agents working with traditional CLIs face two problems:

1. **No introspection.** They have to know commands and flags ahead of time.
2. **Mixed output.** Human prose and machine fields are jumbled together.

ShipItKit fixes both by giving agents:

- A **single bootstrap call** that returns everything they need.
- A **typed, versioned schema** they can parse without screen-scraping.
- An explicit **`nextAction`** field — what to call next, with what flags.
- An explicit **`nextQuestion`** — the single best follow-up to ask the human.

## Quick start

```bash
shipit ai-session --goal beta
shipit ai-session --goal release --path /path/to/project
shipit ai-session --goal beta --platform android
```

Output is always JSON when invoked this way.

## Payload shape

```jsonc
{
  "contractVersion": "1",
  "goal": "beta",
  "platform": "ios",
  "appConfig": [
    {
      "keyPath": "app.scheme",
      "value": "MyApp",
      "source": "detected",       // detected | inferred | assumed | unresolved
      "confidence": "high",       // high | medium | low
      "why": "Found single shared scheme in MyApp.xcworkspace."
    }
  ],
  "missing": [
    {
      "keyPath": "app_store_connect.key_id",
      "envVar": "ASC_KEY_ID",
      "acceptedFormats": ["10-character key id"],
      "exampleSource": "App Store Connect → Users and Access → Integrations",
      "preferFile": false,
      "description": "API key identifier from App Store Connect."
    }
  ],
  "ambiguities": [
    {
      "keyPath": "app.scheme",
      "candidates": ["MyApp", "MyAppDev", "MyAppQA"],
      "why": "Multiple runnable schemes found; user must pick one."
    }
  ],
  "readiness": {
    "blockers": ["Missing ASC_PRIVATE_KEY"],
    "missingSecrets": ["ASC_PRIVATE_KEY"],
    "signingRisk": "medium"
  },
  "shipfileSuggestion": "...generated YAML body...",
  "nextAction": {
    "command": "shipit generate --goal beta",
    "rationale": "All inputs ready; create the Shipfile."
  },
  "nextQuestion": {
    "id": "asc.private_key.location",
    "prompt": "Where is your ASC .p8 file?",
    "answerType": "string"
  },
  "agentPrompt": "...full system prompt for the AI..."
}
```

## Inference metadata

Every inferred value carries provenance via ``InferredConfigEntry``:

- ``InferenceSource`` — `.detected`, `.inferred`, `.assumed`, or `.unresolved`.
- ``InferenceConfidence`` — `.high`, `.medium`, or `.low`.
- `why` — a short human-readable rationale.

This lets agents distinguish "I read this from the Xcode project, trust it" from "I'm guessing based on the directory name, please confirm".

## Resolving ambiguities

If your project has multiple runnable schemes, multiple bundle IDs across configurations, or several `*.xcworkspace` candidates, those land in the `ambiguities` array. An agent should:

1. Ask the user a single targeted question (use the `nextQuestion` value).
2. Re-run `ai-session --goal <goal>` after the user supplies the choice (typically by editing `Shipfile.yml` or exporting an env var).
3. Continue when `ambiguities` is empty.

## Non-interactive generation

When agents are confident enough to write a Shipfile without further user input, they call:

```bash
shipit generate --goal beta --non-interactive
```

This uses ``ProjectInspector`` for the same accurate scheme/bundle/team detection, writes `Shipfile.yml`, and returns a JSON result listing any unresolved fields.

## Goal-scoped schema

Agents can fetch the slice of the action schema relevant to a single goal:

```bash
shipit schema --workflow beta --output json
```

This avoids dumping every action's options when the agent only cares about a single workflow path.

## Composite-action awareness

If the user already has `custom_actions:` declared, they appear in the generated `agentPrompt`. This nudges the agent to **prefer reusing an existing composite** over duplicating its step sequence — see <doc:CompositeActions>.

## Programmatic use

```swift
import ShipItKit

let inspection = try await ProjectInspector(rootPath: ".").inspect()
let payload = AISessionBuilder().build(
    goal: .beta,
    inspection: inspection,
    hasExistingShipfile: false,
    platform: .ios
)
let json = try JSONReporter().encodeAny(payload)
print(json)
```

## Versioning

The contract version is at ``AISessionBuilder/contractVersion``. A bump means any of:

- Field renamed or removed.
- Field's semantics changed.
- A new required field is added that older agents must understand to behave correctly.

Strictly additive changes (e.g. a new optional field) do not bump the contract version.

## See also

- ``AISessionBuilder``
- ``AISessionPayload``
- ``ProjectInspector``
- ``ShipfileSuggester``
- ``InferredConfigEntry``
- ``SecretDescriptor``
- <doc:CompositeActions>

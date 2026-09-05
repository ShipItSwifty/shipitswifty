# ShipItSwifty — Agent Index

This is a compact navigation guide for agents working in this repository. Use it to find the right source of truth quickly instead of reading the full docs set on every task.

## Purpose

- `ShipItSwifty` is a Swift 6 release-automation toolkit for iOS and Android.
- `ShipItKit` contains the domain logic and machine-facing contracts.
- `shipit` is the CLI layer over that library.

## Authoritative sources

| Concern | Source of truth |
|---|---|
| Runtime config resolution | `Sources/ShipItKit/Config/ConfigResolver.swift`, `Sources/ShipItKit/Config/ResolvedConfig.swift` |
| Shipfile model | `Sources/ShipItKit/Config/Shipfile.swift` |
| Environment variable mapping | `Sources/ShipItKit/Config/Environment.swift` |
| Built-in action option schema | `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift` |
| AI-session JSON contract | `Sources/ShipItKit/Introspection/AISessionTypes.swift`, `Sources/ShipItKit/Introspection/AISessionBuilder.swift` |
| Action behavior | `Sources/ShipItKit/Actions/<ActionName>.swift` |
| CLI command surface | `Sources/CLI/Commands/` |
| Executable behavior spec | `Tests/ShipItKitTests/`, `Tests/CLITests/` |

## Start here by task

| Task | Start here |
|---|---|
| Config resolution bug or feature | `Sources/ShipItKit/Config/ConfigResolver.swift`, `ResolvedConfig.swift`, `Environment.swift`, `Shipfile.swift` |
| Action implementation or regression | `Sources/ShipItKit/Actions/`, matching tests in `Tests/ShipItKitTests/` |
| Workflow or custom action behavior | `Sources/ShipItKit/Actions/WorkflowTypes.swift`, `CompositeAction.swift`, workflow-related tests |
| Schema or validation drift | `BuiltInSchemaCatalog.swift`, `SchemaValidator`, `ShipfileValidator`, related tests |
| AI-session output drift | `AISessionTypes.swift`, `AISessionBuilder.swift`, `AISessionTests.swift` |
| CLI parsing or output behavior | `Sources/CLI/Commands/`, `Tests/CLITests/` |
| Coverage/reporting behavior | `Sources/ShipItKit/Actions/Coverage.swift`, parser helpers, `CoverageActionTests.swift` |
| Docs sync work | `AGENTS.md`, `docs/features.md`, `docs/configuration-reference.md`, `docs/architecture.md` |

## Change impact map

Use this when deciding what must change together.

| If you change... | Also check/update... |
|---|---|
| An action `Options` or `Result` type | `BuiltInSchemaCatalog.swift`, tests, `docs/features.md`, `AGENTS.md` if command guidance changed, `AISessionBuilder.swift` if agent-facing guidance changed |
| Shipfile schema | `Shipfile.swift`, `BuiltInSchemaCatalog.swift`, `docs/configuration-reference.md`, validation tests |
| `ai session` payload shape or semantics | `AISessionTypes.swift`, `AISessionBuilder.swift`, `docs/architecture.md`, `AGENTS.md`, `AISessionTests.swift` |
| CLI command flags or subcommands | `Sources/CLI/Commands/`, `AGENTS.md`, `docs/features.md`, CLI tests |
| Runtime config behavior | `ConfigResolver.swift`, `ResolvedConfig.swift`, `Environment.swift`, config tests |
| Workflow/composite execution | `WorkflowTypes.swift`, `CompositeAction.swift`, workflow/composite tests |

## Recommended first-read paths

- `Package.swift`
- `AGENTS.md`
- `Sources/ShipItKit/Config/ConfigResolver.swift`
- `Sources/ShipItKit/Config/ResolvedConfig.swift`
- `Sources/ShipItKit/Actions/`
- `Sources/ShipItKit/Introspection/`
- `Tests/ShipItKitTests/`

## Validation commands

```bash
swift build
swift test --filter ShipItKitTests
swift test --filter CLITests
swift test --enable-code-coverage
```

Use more targeted filters when the change is localized, for example:

```bash
swift test --filter AISessionTests
swift test --filter IntrospectionTests
swift test --filter GenerateProjectActionTests
swift test --filter WorkflowAutoGenerationTests
```

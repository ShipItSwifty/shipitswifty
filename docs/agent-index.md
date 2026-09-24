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
| Reusable tool wrappers (common components) | `Sources/XcodeBuildKit/`, `Sources/GradleKit/` (Gradle, Adb, Bundletool, Emulator), `Sources/AndroidCLIKit/`, `Sources/XcodeGenKit/` |
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
| Test execution, reruns, test reports | `Sources/ShipItKit/Actions/Test.swift`, `Sources/ShipItKit/TestResults/`, `TestActionAndroidRerunTests.swift` |
| Android device / emulator orchestration | `Sources/ShipItKit/Utilities/AndroidDeviceProvisioner.swift`, `AndroidDeviceProvisionerTests.swift` |
| New `xcodebuild` / `gradlew` / `adb` / `bundletool` / `emulator` / `android` flag or subcommand | The matching tool-wrapper library above (not ShipItKit), then its tests in `Tests/<Library>Tests/` |
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
| A tool-wrapper library's public API | Its tests (assert the exact argv), the wrapper table in `docs/features.md` ("Standalone tool libraries"), and ShipItKit call sites that build the same arguments by hand |

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

## Verifying on Linux (no local Swift toolchain)

Cloud agent sessions usually run on Linux. Use Docker (see `Makefile`):

```bash
make build-linux     # swift build in swift:6.3.1-noble
make test-linux      # skips IntegrationTests, XcodeBuildKitTests, XcodeGenKitTests
```

- `XcodeBuildKit`, `XcodeGenKit`, and every `#if os(macOS)` block in ShipItKit (iOS test/build paths, simctl, xcresult parsing) do **not** compile on Linux. Changes there are only verified by the macOS CI job — say so explicitly when reporting.
- Write new tests Linux-runnable where possible (no `#if os(macOS)` around Android, config, or parsing tests) so they run in both CI jobs.
- CI enforces `swift-format lint --strict` (config: `.swift-format`); the Linux image ships `swift format`, so run `swift format --in-place --configuration .swift-format <files>` on changed files.


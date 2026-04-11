# ShipItSwifty — Agent Guidance

This file is the single source of truth for AI agents working in this repository (Claude Code, OpenAI Codex, etc.).

## Skills

When working on this project, invoke these skills as appropriate:

- **`swift-concurrency`** — use whenever touching `async/await`, `actor`, `Sendable`, `Task`, or debugging data-race/concurrency warnings. This project is Swift 6 strict-concurrency throughout.
- **`swift-concurrency-pro`** — use when *reviewing* existing concurrency code for correctness, reentrancy safety, structured vs unstructured task choices, or cancellation handling. Complements `swift-concurrency` for review-oriented work.
- **`swift-testing-pro`** — use when writing, reviewing, or improving tests. All tests in this project use Swift Testing (`@Test`, `#expect`, `#require`). Use for async test patterns, parameterized tests, and test quality review.
- **`swift-testing-expert`** — use for deeper Swift Testing questions: traits, tags, parallel execution safety, test plans, or migrating any remaining XCTest patterns.
- **`spm-build-analysis`** — use when investigating slow builds, package resolution issues, dependency graph shape, or build plugin overhead in the SPM manifest.
- **`xcode-project-analyzer`** — use when auditing xcodebuild invocation behavior, build settings, scheme configuration, or diagnosing why `xcodebuild` exits unexpectedly (e.g. exit 64/74).
- **`xcode-build-fixer`** — use when applying approved build optimization changes after analysis by `xcode-project-analyzer`.

## Commands

```bash
# Build
swift build

# Run all tests with coverage
swift test --enable-code-coverage

# Run a single test (by filter)
swift test --filter ShipItKitTests.BuildActionTests

# Run specific test target
swift test --filter CLITests

# Run CLI
swift run shipit --help
swift run shipit build --scheme MyApp
swift run shipit run beta --ci --output json

# AI-first entrypoint (canonical machine-oriented command)
swift run shipit ai-session --goal beta
swift run shipit ai-session --goal release --path /path/to/project

# Non-interactive init (agents/CI)
swift run shipit init --goal beta --non-interactive --output json

# Goal-scoped schema slice
swift run shipit schema --workflow beta --output json

# Structured dry-run (returns JSON step list)
swift run shipit run beta --dry-run --output json
```

> **Prerequisite:** Requires access to the remote `SwiftyShell` Swift package dependency during `swift build` and `swift test`.

## App Store Connect credentials (for ASC-backed features)

Set these environment variables:
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY` (raw PEM) or `ASC_PRIVATE_KEY_PATH` (file path)

## Architecture

ShipItSwifty is a Swift 6 CLI toolkit for iOS app release automation. There are two products:

- **`ShipItKit`** — reusable library; all domain logic lives here
- **`shipit`** (CLI) — thin argument-parsing layer over `ShipItKit`

### Core execution model

```
Shipfile.yml / CLI flags / env vars
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient, platform)
        ↓
  ActionRegistry (actor) — maps action names → ActionDescriptors
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope (JSON-serializable)
```

### Key abstractions

| Type | Role |
|---|---|
| `Action` | Protocol — one unit of work (`build`, `archive`, `testflight`, …). Defines typed `Options` and `Result`. |
| `ActionDescriptor` | Type-erased wrapper produced by `Action.descriptor(for:)`. Registered in `ActionRegistry`. |
| `ActionRegistry` | `actor` — serializes concurrent registration and lookup by name. |
| `Workflow` / `WorkflowStep` | A named sequence of steps; defined in Shipfile YAML or via `@WorkflowBuilder` DSL. |
| `ActionContext` | Passed to every `Action.run(...)`. Carries `ShellContext` (SwiftyShell), `Logger`, `ResolvedConfig`, `AppStoreConnectClient`. |
| `ConfigResolver` | Merges CLI flags → env vars (`SHIPIT_*`) → Shipfile.yml → built-in defaults. |
| `AppStoreConnectClient` | JWT-authenticated HTTP client for the ASC REST API. |

### Config resolution priority

CLI flags > `SHIPIT_*` env vars > `Shipfile.yml` > built-in defaults. Shipfile supports `${ENV_VAR}` expansion.

### Source layout

```
Sources/
  ShipItKit/
    Actions/          # One file per action (Build, Archive, TestFlight, …)
    AppStoreConnect/  # ASC client, JWT, upload service, models
    CodeSigning/      # Keychain, cert/profile management, cert vault
    Config/           # Shipfile model, ConfigResolver, ResolvedConfig, Environment
    Introspection/    # ProjectInspector, ShipfileSuggester, BuiltInSchemaCatalog,
                      # SchemaTypes, SchemaValidator, ShipfileValidator,
                      # AISessionTypes, AISessionBuilder
    Plugin/           # ShipItPlugin protocol, ActionRegistry, PluginRegistry
    Utilities/        # JSONValue, Logger, ShipItError, RetryPolicy, JSONReporter
    Versioning/       # VersionBumper, BuildNumberSource
    Notifications/    # Notifier
    XcodeBuild/       # xcodebuild wrapper + options
    Xcrun/            # xcrun / simctl wrappers
  CLI/
    Commands/         # One file per shipit subcommand
    Formatters/       # HumanFormatter, JSONFormatter
    ShipItCLI.swift   # @main entry point + GlobalOptions mixin
```

### CLI global options

Every subcommand inherits `GlobalOptions`: `--shipfile`, `--output (human|json)`, `--verbose`, `--ci`, `--dry-run`.

## Testing patterns

- **Shell mocking:** Inject a `MockExecutor` from SwiftyShell. Use `ActionContext.mock(executor:)` — it wires a `MockExecutor` into a fully-formed `ActionContext` without spawning real processes.
- **HTTP mocking:** Use `makeClient(responses:)` + `MockURLProtocol` from `Tests/ShipItKitTests/TestSupport.swift` to queue canned HTTP responses for ASC API tests.
- All tests use Swift Testing (`@Test`) where possible per project conventions.

## Plugin system

Plugins are statically linked Swift packages. Conform to `ShipItPlugin` (provides `name`, `description`, `actions: [ActionDescriptor]`), then register at CLI bootstrap. Runtime dylib loading is out of scope for v1.

## Architecture rules

These are hard constraints — never violate them:

1. **All shell execution MUST go through SwiftyShell** — never use `Foundation.Process` directly
2. **All App Store Connect API calls MUST go through `AppStoreConnectClient`** — no raw HTTP requests
3. **All public types MUST be `Sendable`** — Swift 6 strict concurrency throughout
4. **All async work MUST use structured concurrency** — `async let`, `TaskGroup`; never detached tasks
5. **Actions MUST derive behavior solely from `Options` and `ActionContext`** — no hidden global mutable state

## File organization

- One `Action` per file in `Sources/ShipItKit/Actions/`
- One `Command` per file in `Sources/CLI/Commands/`
- Models in `Models/` subdirectories, colocated with their module

## Adding a new action

1. Create `Sources/ShipItKit/Actions/NewAction.swift` conforming to `Action`
2. Add `Options: Codable & Sendable` with all configurable parameters
3. Add `Result: Codable & Sendable` for typed output
4. Write DocC doc comment with `## Usage` section
5. Create `Sources/CLI/Commands/NewActionCommand.swift`
6. Add to Shipfile schema in `Sources/ShipItKit/Config/Shipfile.swift`
7. Write tests in `Tests/ShipItKitTests/NewActionTests.swift`
8. **Update `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift`** — add or update the `actionSchemas()` entry and its `*Options()` helper to reflect all new/changed `Options` fields
9. **Update `docs/features.md`** — add or update the relevant feature table row(s) to reflect the new capability
10. **Run `swift build` and `swift test --filter ShipItKitTests`** to confirm no regressions

## Modifying an existing action

Whenever you add, remove, or rename an `Options` or `Result` field on any existing action, you **must** also update all of the following in the same change:

- `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift` — the action's `*Options()` helper
- `docs/features.md` — the relevant feature table row(s)
- `Tests/ShipItKitTests/<ActionName>Tests.swift` — add tests for the new/changed behaviour

Failure to keep these three in sync will cause `shipit schema` and `shipit ai-session` to return stale information to agents and CI.

## Common task reference

| Task | How |
|---|---|
| Run xcodebuild | `XcodeBuild(context:).option(.scheme("X")).trailingArgument("build").run()` |
| Run git operations | `Git(context:).workingDirectory(path).status().run()` |
| Call ASC API | `context.appStoreConnect.get("/v1/apps")` |
| Upload asset | `context.appStoreConnect.uploadAsset(at:reservation:)` |
| Read Info.plist | `Command("plutil", "-extract", key, "raw", plistPath).run(in: context.shell)` |
| Generate JWT | `context.appStoreConnect.jwtGenerator.cachedOrNewToken()` |

## Reference docs

Detailed reference material lives in `docs/`:

- [`docs/architecture.md`](docs/architecture.md) — layer diagram, core type definitions, CLI commands, ASC client
- [`docs/features.md`](docs/features.md) — feature catalog, roadmap, tool comparison
- [`docs/configuration-reference.md`](docs/configuration-reference.md) — Shipfile.yml keys, env vars, resolution order
- [`docs/testing.md`](docs/testing.md) — testing strategy, examples, coverage goals
- [`docs/security.md`](docs/security.md) — secrets management, threat mitigations
- [`docs/plugin-development.md`](docs/plugin-development.md) — plugin authoring guide
- [`docs/ci-setup.md`](docs/ci-setup.md) — GitHub Actions, GitLab CI, Bitrise
- [`docs/walkthrough.md`](docs/walkthrough.md) — step-by-step getting started

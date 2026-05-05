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
swift test --filter XcodeBuildKitTests
swift test --filter GradleKitTests
swift test --filter XcodeGenKitTests

# Linux / Docker (skips macOS-only targets automatically)
make build-linux            # build via direct volume mount
make test-linux             # run Linux-compatible tests via direct volume mount
make test-linux-coverage    # same + --enable-code-coverage
make shell-linux            # interactive shell inside container
make docker-build           # build local image (caches SPM deps as a layer)
make docker-test            # run tests inside local image
make docker-shell           # interactive shell inside local image
make help                   # list all Makefile targets

# Run CLI
swift run shipit --help
swift run shipit build --scheme MyApp
swift run shipit sign sync --type appstore
swift run shipit run beta --ci --output json

# Android build / test / archive
swift run shipit build --platform android
swift run shipit test --platform android
swift run shipit archive --platform android
swift run shipit lint --platform android
swift run shipit play-store --platform android

# Validate subcommand family
swift run shipit validate                          # default: validate yml
swift run shipit validate yml                      # Shipfile structure and workflow semantics
swift run shipit validate metadata                 # App Store metadata / precheck rules
swift run shipit validate archive --archive-path ./build/MyApp.xcarchive
swift run shipit validate archive --ipa ./build/export/MyApp.ipa
swift run shipit validate bundle --bundle ./build/app-release.aab   # Android AAB / APK validation
swift run shipit validate all                      # yml + metadata + archive in sequence
swift run shipit precheck                          # backwards-compat alias: validate metadata

# AI-first entrypoint (canonical machine-oriented command)
swift run shipit ai-session --goal beta
swift run shipit ai-session --goal release --path /path/to/project
swift run shipit ai-session --goal beta --platform android   # Android-specific agent prompt

# Guided Shipfile generation
swift run shipit generate --goal beta
swift run shipit generate --goal beta --non-interactive

# Goal-scoped schema slice
swift run shipit schema --workflow beta --output json

# Structured dry-run (returns JSON step list)
swift run shipit run beta --dry-run --output json

# Coverage — read and summarize native coverage artifacts
swift run shipit coverage                                      # auto-discover, first-party default
swift run shipit coverage --first-party-only --targets        # per-target summary
swift run shipit coverage --files                             # per-file breakdown
swift run shipit coverage --format json                       # machine-readable output
swift run shipit coverage --format markdown                   # PR comment / CI summary
swift run shipit coverage --summary                           # single overall line
swift run shipit coverage --xcresult ./build/MyApp-tests.xcresult  # iOS explicit path
swift run shipit coverage --platform android                  # Android (JaCoCo XML)
swift run shipit coverage --platform android --report ./app/build/reports/jacoco/test/jacocoTestReport.xml
swift run shipit coverage --include-target MyFeatureKit       # include specific target
swift run shipit coverage --exclude-target GoogleSignIn       # exclude vendor targets
swift run shipit coverage --sort name --limit 10              # alphabetical, capped
```

> **Prerequisite:** Requires access to the remote `SwiftyShell` Swift package dependency during `swift build` and `swift test`.

## Custom actions (composite workflow steps)

`Shipfile.yml` supports a `custom_actions:` block where users define reusable, parameterized step sequences. A custom action is invoked from a workflow the same way as a built-in:

```yaml
custom_actions:
  build_and_sign:
    description: "Test, archive, and export with a chosen export method."
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
      options: { method: app-store }
    - action: testflight
  adhoc:
    - action: build_and_sign
      options: { method: ad-hoc }
```

**Parameter substitution:** Inside a step's `options:` block, string values may reference declared parameters with `{{param.NAME}}`. This delimiter is deliberately chosen to avoid collisions with:

- Shipfile's own `${ENV_VAR}` expansion (different delimiter; env expansion runs *before* composite substitution, so you can mix them: `"{{param.track}}-${DEPLOY_ENV}"`).
- GitHub Actions `${{ env.X }}` / `${{ secrets.X }}`.
- CircleCI `<< parameters.X >>`.
- Xcode Cloud / shell `$VAR` / `${VAR}`.

**Rules enforced by `shipit validate yml`:**
- Custom action names must not collide with built-in action names.
- Each step's `action:` must resolve to a built-in or another composite.
- Every `{{param.NAME}}` reference must match a declared parameter.
- Required parameters (no `default:`) must be supplied at the call site.
- Composite-to-composite references must be acyclic.

**Agent guidance:** `shipit ai-session` enumerates the user's declared custom actions in the generated `agentPrompt` so agents prefer reusing an existing composite over duplicating its step sequence in a new workflow.

See `docs/configuration-reference.md` for the full schema and examples.

## App Store Connect credentials (for ASC-backed features)

Set these environment variables:
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY` (raw PEM) or `ASC_PRIVATE_KEY_PATH` (file path)

## iOS manual signing credentials

For `code_signing.type: manual`, ShipIt can install a `.p12` certificate and provisioning profile before archive/export.

Local paths are preferred when present; base64 values are used as CI fallback.

Set these environment variables as needed:
- `SHIPIT_CODE_SIGNING__P12_PATH` or `P12_BASE64`
- `P12_PASSWORD`
- `SHIPIT_CODE_SIGNING__PROVISIONING_PROFILE_PATH` or `PROVISIONING_PROFILE_BASE64`

## Google Play credentials (for Android-backed features)

Set one of these environment variables:
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (raw JSON content)
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` (file path)

## Architecture

ShipItSwifty is a Swift 6 CLI toolkit for iOS and Android app release automation. There are five products:

- **`XcodeBuildKit`** — standalone library; typed `xcodebuild` wrapper, options, destination discovery, `xcode-select`. Depends only on SwiftyShell.
- **`GradleKit`** — standalone library; typed Gradle wrapper (tasks, flags, properties), plus `adb`, `bundletool`, and `emulator` wrappers. Depends only on SwiftyShell.
- **`XcodeGenKit`** — standalone library; typed `xcodegen` wrapper and options. Depends only on SwiftyShell.
- **`ShipItKit`** — reusable library; all domain logic lives here. Depends on the three tool libraries above.
- **`shipit`** (CLI) — thin argument-parsing layer over `ShipItKit`

`XcodeBuildKit`, `GradleKit`, and `XcodeGenKit` are independently consumable via SwiftPM — users who only need build tool wrappers can depend on them without pulling in ShipItKit or any of its heavier dependencies. `ShipItKit` re-exports all three via `@_exported import`, so existing consumers see no API change.

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
| `ActionContext` | Passed to every `Action.run(...)`. Carries `ShellContext` (SwiftyShell), `Logger`, `ResolvedConfig`, `AppStoreConnectClient`. Provides `ensureProjectGenerated()` for auto-generation. |
| `ConfigResolver` | Merges CLI flags → env vars (`SHIPIT_*`) → Shipfile.yml → built-in defaults. |
| `AppStoreConnectClient` | JWT-authenticated HTTP client for the ASC REST API. |
| `GenerateProjectAction` | Generates `.xcodeproj` from a spec file (XcodeGen, Tuist). Auto-invoked by `Workflow.run()` before Xcode-dependent steps. |
| `ProjectSpecVersionSource` | Reads/writes version values directly in YAML spec files for `project_spec` versioning source. |
| `DestinationDiscovery` | Discovers available xcodebuild destinations. Used by `TestAction` for automatic simulator selection. |

### Config resolution priority

CLI flags > `SHIPIT_*` env vars > `Shipfile.yml` > built-in defaults. Shipfile supports `${ENV_VAR}` expansion.

### Source layout

```
Sources/
  XcodeBuildKit/      # Standalone: xcodebuild wrapper, options, xcode-select, destination discovery
  GradleKit/          # Standalone: gradlew wrapper, tasks, flags, properties, adb, bundletool, emulator
  XcodeGenKit/        # Standalone: xcodegen wrapper and options
  ShipItKit/
    Actions/          # One file per action (Build, Archive, TestFlight, …)
    AppStoreConnect/  # ASC client, JWT, upload service, models
    CodeSigning/      # Keychain, cert/profile management, cert vault
    Config/           # Shipfile model, ConfigResolver, ResolvedConfig, Environment
    Introspection/    # ProjectInspector, ShipfileSuggester, BuiltInSchemaCatalog,
                      # SchemaTypes, SchemaValidator, ShipfileValidator,
                      # AISessionTypes, AISessionBuilder
    Plugin/           # ShipItPlugin protocol, ActionRegistry, PluginRegistry
    ReExports/        # @_exported import for XcodeBuildKit, GradleKit, XcodeGenKit
    Utilities/        # JSONValue, Logger, ShipItError, RetryPolicy, JSONReporter
    Versioning/       # VersionBumper, BuildNumberSource
    Notifications/    # Notifier
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
10. **Update `AGENTS.md`** — if the action changes or adds CLI commands, update the Commands section; if it changes agent workflows, update the relevant sections
11. **Update `Sources/ShipItKit/Introspection/AISessionBuilder.swift`** — if the action affects what agents should do (e.g. a new validation or workflow step agents need to know about), update `buildAgentPrompt`, `buildNextAction`, or `buildNextQuestion` accordingly
12. **Run `swift build` and `swift test --filter ShipItKitTests`** to confirm no regressions

## Modifying an existing action

Whenever you add, remove, or rename an `Options` or `Result` field on any existing action, you **must** also update all of the following in the same change:

- `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift` — the action's `*Options()` helper
- `docs/features.md` — the relevant feature table row(s)
- `Tests/ShipItKitTests/<ActionName>Tests.swift` — add tests for the new/changed behaviour
- `AGENTS.md` — update Commands section and any agent workflow guidance that references the changed action
- `Sources/ShipItKit/Introspection/AISessionBuilder.swift` — update any hardcoded command strings or agent prompt content that references the changed action

Failure to keep these in sync will cause `shipit schema` and `shipit ai-session` to return stale information to agents and CI.

## Mandatory change checklist

Every non-trivial code change (new feature, changed behaviour, new/renamed command) **must** include all applicable items from this checklist before it is considered complete:

| Change type | Required updates |
|---|---|
| New CLI command or subcommand | `AGENTS.md` Commands section, `docs/features.md`, `AISessionBuilder` agentPrompt if agents need to know |
| New or modified `Action` | `BuiltInSchemaCatalog`, `docs/features.md`, tests, `AGENTS.md` if command surface changes, `AISessionBuilder` if agent workflow changes |
| Changed exit code or error type | `ShipItError`, `CLIHelpers.errorSuggestions`, `docs/architecture.md` exit code table |
| Changed `ai-session` JSON contract | `AISessionTypes.swift` version bump, `AISessionBuilder`, `docs/architecture.md`, `AGENTS.md` |
| Changed Shipfile schema | `BuiltInSchemaCatalog`, `Shipfile.swift`, `docs/configuration-reference.md` |
| New backwards-compat alias | Document in `AGENTS.md` Commands section with `# backwards-compat alias:` comment |

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

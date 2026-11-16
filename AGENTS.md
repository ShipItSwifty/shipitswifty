# ShipItSwifty — Agent Guidance

The single source of truth for AI agents working in this repository (Claude Code, OpenAI Codex, …).
It holds the rules. Maps, recommendations and contracts live in the docs it links; read those only
when the task touches them.

ShipItSwifty is a Swift 6 CLI and library for iOS and Android release automation. `ShipItKit` holds
the domain logic; `shipit` is the thin CLI over it.

## Response modes

Use the lightest mode that fits.

- **Quick scan** (default for broad prompts like "what can improve here?"): read the first-read files
  below plus the most relevant implementation files, then answer with the highest-leverage findings.
- **Deep audit**: only when asked for a deep review or repo-wide analysis. Ask one short scope question
  before escalating a broad question into one. Cross-check code, tests, schema, docs and agent surfaces.
- **Implementation** (default for change requests): read the target code path, its immediate
  dependencies and the tests to update, then implement and verify. Don't pause for a full audit unless
  the change clearly touches several contracts.

First read on a cold start: `Package.swift`, `Sources/ShipItKit/Config/ConfigResolver.swift`,
`ResolvedConfig.swift`, `Sources/ShipItKit/Actions/`, `Sources/ShipItKit/Introspection/`,
`Tests/ShipItKitTests/`. Treat `ConfigResolver` + `ResolvedConfig` as the runtime source of truth.
For where to start on a given task and what changes together, see [`docs/agent-index.md`](docs/agent-index.md).

## Hard rules

1. **All shell execution goes through SwiftyShell**, never `Foundation.Process`.
2. **Tool arguments come from [`cli-wrappers`](https://github.com/ShipItSwifty/cli-wrappers)**. Never hand-build
   `xcodebuild` / `gradlew` / `adb` / … argument strings in ShipItKit; add the flag to the wrapper first (below).
3. **Terminal UX comes from [`SwiftyTerminal`](https://github.com/maniramezan/SwiftyTerminal)** (colors, prompts,
   menus, spinners, progress, formatted output), shared with Amoo. `HumanFormatter` and `GenerateCommand`'s prompts
   are thin adapters. Add new terminal UX there, not in `Sources/CLI`. It tracks `main` until `0.1.0`.
4. **All App Store Connect calls go through `AppStoreConnectClient`** (the external `AppStoreConnectKit`), never raw HTTP.
5. **All public types are `Sendable`**: Swift 6 strict concurrency throughout.
6. **All async work uses structured concurrency** (`async let`, `TaskGroup`); never detached tasks.
7. **Actions derive behavior only from `Options` and `ActionContext`**: no hidden global mutable state, no
   `ProcessInfo` reads inside an action (resolve environment in `ConfigResolver`).
8. **Never use "lane"** for anything of ShipIt's own; it is fastlane's term. Say workflow (a named sequence of steps)
   and action (the unit one step runs). "Lane" is allowed only when describing fastlane itself.
9. **Swift Testing** (`@Test`, `#expect`, `#require`) for all new tests.
10. Apple's `swift format` (config `.swift-format`) is the only formatter. Short, obvious early exits may stay on one
    line (`guard let self else { return }`); complex conditions, error construction and real work get multiline bodies.

## Commands

```bash
swift build
swift test --filter ShipItKitTests
swift test --filter CLITests
swift test --enable-code-coverage
swift test --filter ShipItKitTests.BuildActionTests        # one suite

# This repo's own checks, as Shipfile workflows
swift run shipit run format
swift run shipit test --workflow ci-macos                  # or ci-linux

# Linux / Docker (skips macOS-only targets); see `make help`
make build-linux
make test-linux

# Try the CLI
swift run shipit --help
swift run shipit ai session --goal beta
swift run shipit run beta --dry-run --output json
```

Requires network access to the remote package dependencies on first build. The full command surface is in
[`docs/features.md`](docs/features.md) and `shipit <command> --help`.

Backwards-compat aliases (keep them working and listed here):

```bash
shipit precheck   # backwards-compat alias: shipit validate metadata
```

## Skills

Repository skills live in `agent-skills/`; `.claude/skills/` holds stubs that point there, so edit only
`agent-skills/`. Read the matching `SKILL.md` when the task applies:

- **[`add-action`](agent-skills/add-action/SKILL.md)**: adding or changing an action's `Options` / `Result`. Walks the full sync checklist.
- **[`verify-linux`](agent-skills/verify-linux/SKILL.md)**: building, formatting and testing from Linux with Docker, and what that cannot verify.

Also use, when they apply: `swift-concurrency` (writing async/actor/`Sendable` code),
`swift-concurrency-pro` (reviewing it), `swift-testing-pro` / `swift-testing-expert` (tests),
`spm-build-analysis` (slow builds, resolution, dependency graph), `xcode-project-analyzer` /
`xcode-build-fixer` (xcodebuild behavior, exit 64/74).

`shipit ai skills` is a different thing: built-in playbooks shipped in the binary for agents working on an
*end user's* project (`AISkillsCatalog.swift`).

## Architecture

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

Config priority: CLI flags > `Shipfile.yml` > `SHIPIT_*` env vars > `.env` (next to the Shipfile) > defaults.
The Shipfile supports `${ENV_VAR}` expansion.

ShipItKit builds on external packages and imports each module explicitly; nothing is re-exported. Those
tracking `main` do so until 1.0.

| Package | Provides | Boundary in this repo |
|---|---|---|
| [`cli-wrappers`](https://github.com/ShipItSwifty/cli-wrappers) | One typed wrapper per tool (`XcodeBuildKit`, `XcrunKit`, `GradleKit`, `AdbKit`, `EmulatorKit`, `BundletoolKit`, `AndroidCLIKit`, `FlutterKit`, `ReactNativeKit`, `SwiftPMKit`, `SecurityKit`, `PlutilKit`, `XcodeGenKit`, `FrameitKit`) | Call sites import the product they use |
| [`mobile-kits`](https://github.com/ShipItSwifty/mobile-kits) | Mechanisms shared with Amoo: `MobileCore` (`AppFramework`, `JSONValue`), `MobileBuild` (`XcodeBuilder`, `GradleBuilder`, `XcodeTestRunner`, `JavaScriptProject`), `MobileTesting` (result parsers), `MobileDevices` (device claims), `MobileProject` (`FrameworkDetector`) | `BuildBridge.swift` adapts builders and maps `BuildFailure` → `ShipItError`. Retries, flaky classification, evidence, reports and coverage stay here (`Test.swift`, `NativeTestExecution.swift`) |
| [`app-store-connect-mcp`](https://github.com/ShipItSwifty/app-store-connect-mcp) | `AppStoreConnectKit` (client, JWT, rate limiter, DTOs, Xcode Cloud read API), macOS-only `AppStoreConnectUploadKit` | `mappingASCErrors { }` in `AppStoreConnect/ASCErrorBridge.swift`. Actions pass `context.ascCredentials` + `context.shell`, not the whole context |
| [`google-play-store-mcp`](https://github.com/ShipItSwifty/google-play-store-mcp) | `GoogleAuthKit` (service-account JWT, Workload Identity Federation), `GooglePlayKit` (Play API, edit → upload → track → commit) | `mappingGoogleErrors { }` in `GooglePlay/GooglePlayErrorBridge.swift`. `FirebaseAppDistributionClient` stays here on top of `GoogleAuthKit` |
| [`SwiftyShell`](https://github.com/maniramezan/SwiftyShell), [`SwiftyTerminal`](https://github.com/maniramezan/SwiftyTerminal) | Process execution and mocking; terminal UX | Rules 1 and 3 |

Artifact paths come from what the tools report (`-showBuildSettings`, `output-metadata.json`); a
conventional path is only the fallback for a Gradle task skipped as up to date. The Play API's
`applications.dataSafety` is write-only: a published Data safety declaration can't be read back.

`Platform` (`.ios` / `.android`) and `AppFramework` (`.native` / `.flutter` / `.reactNative` / `.kmp`) are
independent axes: the platform picks the distribution pipeline, the framework picks how the artifact is compiled.
Detection, defaults and what to recommend to users are in
[`docs/agent-index.md` → Recommending Shipfile changes](docs/agent-index.md#recommending-shipfile-changes).

Layout: `Sources/ShipItKit/{Actions, Config, Introspection, Plugin, Utilities, Versioning, GitHub,
CodeSigning, Firebase, AppStoreConnect, GooglePlay, Notifications}`, `Sources/CLI/{Commands, Formatters}`.
One `Action` per file in `Actions/`, one command per file in `Commands/`, models in `Models/` next to their module.
Every subcommand inherits `GlobalOptions`: `--shipfile`, `--output (human|json)`, `--verbose`, `--ci`, `--dry-run`.

Plugins are statically linked Swift packages conforming to `ShipItPlugin`, registered at CLI bootstrap.

## Shipfile features agents get wrong

- **Custom actions** (`custom_actions:`) are reusable, parameterized step sequences invoked like built-ins.
  Inside step `options`, `{{param.NAME}}` substitutes a declared parameter. Env expansion (`${VAR}`) runs first.
  `shipit validate yml` enforces: no collision with built-in names, every step resolves, every reference is declared,
  required parameters are supplied, and composites are acyclic. `ai session` lists the user's custom actions so agents
  reuse them, and project auto-generation looks through them recursively. Full schema:
  [`docs/configuration-reference.md`](docs/configuration-reference.md#custom_actions).
- **Workflow tokens** (distinct from `{{param.NAME}}`): top-level steps may use `{{version}}`, `{{build_number}}` and
  `{{version_changed}}` in `options` and `when`, resolved at run time (`Actions/WorkflowTokens.swift`); `when:` skips a
  step (status `skipped`). Prefer tagging inside the workflow (`git` with `tag_name: "v{{version}}"`, gated by
  `when: "{{version_changed}}"`) over shell/jq glue. Top-level steps only, not custom-action substeps.

Credentials: App Store Connect uses `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` or `ASC_PRIVATE_KEY_PATH`.
Manual iOS signing uses `SHIPIT_CODE_SIGNING__P12_PATH` / `P12_BASE64`, `P12_PASSWORD` and
`SHIPIT_CODE_SIGNING__PROVISIONING_PROFILE_PATH` / `PROVISIONING_PROFILE_BASE64` (local paths win). Google Play uses
`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` or `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`. See [`docs/security.md`](docs/security.md)
and [`docs/credential-lookup.md`](docs/credential-lookup.md).

## Testing patterns

- **Shell:** inject a SwiftyShell `MockExecutor` via `ActionContext.mock(executor:)`; assert the exact commands issued.
- **Realistic exit codes:** a failing `gradlew` exits 1 and `xcodebuild` 65. Never mock exit 0 with failure text; it
  hides bugs where a failure throws before later logic (such as reruns) runs.
- **HTTP:** `makeClient(responses:)` + `StubbedURLSession` from `Tests/ShipItKitTests/TestSupport.swift`. Keep the stub
  alive with `defer { stub.invalidate() }`.
- **Scratch directories:** `TemporaryDirectory` from SwiftTestCommons, created in the test that owns the files
  (`defer { try? scratch.remove() }`) and passed to helpers.
- **Linux first:** keep Android, config and parser tests outside `#if os(macOS)` so both CI jobs run them.
- **Real tools:** changes to result parsing, counting or reporting are verified against sample projects, not only
  mocks. See "Verifying against real projects" in [`docs/testing.md`](docs/testing.md).

Before changing test execution, results, evidence, device claims or CI reporting, read
[`docs/testing.md` → Test workflow contracts](docs/testing.md#test-workflow-contracts).

## Making changes

### Adding or changing an action

Use the [`add-action`](agent-skills/add-action/SKILL.md) skill. In short: one file in `Sources/ShipItKit/Actions/`
conforming to `Action`, with `Options` and `Result` both `Codable & Sendable` and a DocC `## Usage` section; register it in
`builtInActionDescriptors()` (`Sources/CLI/Commands/RunCommand.swift`) with its `optionSchema` and `validationRules`, or
workflows and `shipit validate yml` can't see it; add it to `Shipfile.swift`; then sync the surfaces below.

### Adding or extending a tool wrapper

Add the flag, subcommand or task to [`cli-wrappers`](https://github.com/ShipItSwifty/cli-wrappers) first (its
`tool-wrapper` skill), then call it from ShipItKit. While developing, point at a local checkout:

```bash
swift package config set-mirror \
  --original https://github.com/ShipItSwifty/cli-wrappers.git \
  --mirror /path/to/local/cli-wrappers
```

Remove the mirror (`swift package config unset-mirror --original …`) once the change is on `cli-wrappers` `main`, then
`swift package update cli-wrappers`.

### Change checklist

`shipit schema` and `shipit ai session` are not derived from `Options` types, so a change is incomplete until every
surface agrees.

| Change | Also update, in the same change |
|---|---|
| New or changed action `Options` / `Result` | `BuiltInSchemaCatalog` `*Options()` helper, `docs/features.md`, tests, `AISessionBuilder` if agent workflow changes |
| New CLI command or flag | `docs/features.md`, the website CLI reference, `AISessionBuilder` if agents need it |
| Shipfile schema | `Shipfile.swift`, `BuiltInSchemaCatalog`, `docs/configuration-reference.md` |
| Exit code or error type | `ShipItError`, `CLIHelpers.errorSuggestions`, `docs/architecture.md` exit-code table |
| `ai session` JSON contract | `AISessionTypes.swift` version bump, `AISessionBuilder`, `docs/architecture.md` |
| Generated workflow guidance or test options | `AISessionBuilder`, `ShipfileSuggester`, `GenerateCommand`, `docs/features.md`, `docs/configuration-reference.md`, `docs/agent-index.md`, tests |
| Backwards-compat alias | The alias list in this file's Commands section |
| Tool-wrapper API | Land it in `cli-wrappers`, update the package, replace any ShipItKit call site that builds the same arguments |
| New `shipit ai skills` playbook | `AISkillsCatalog.swift` (short; link the authoritative doc), `docs/features.md` |
| Anything user-visible | The website (`ShipItSwifty/website`): guides and reference pages that describe it |

Finish with `swift build` and `swift test --filter ShipItKitTests` (plus `CLITests` for CLI changes).

### Common tasks

| Task | How |
|---|---|
| Build, archive, export, native test | `BuildBridge.swift` over `mobile-kits`' `XcodeBuilder` / `GradleBuilder` / `XcodeTestRunner` |
| Gradle variant task with a test filter | `context.gradle().task(GradleTask.unitTest(variant: "debug").qualified(module: "app").filteringTests(["com.example.FooTest"])).run()` |
| Variant task name | `GradleTask.variantTask(prefix: "bundle", flavor: flavor, variant: variant)`; never `String.capitalized`, which lower-cases camelCase variants |
| Boot / find Android devices | `AndroidDeviceProvisioner(context:logger:).prepare(devices:)`, then `teardown(_:)` |
| Read Info.plist | `Plutil(context: context.shell).extractRaw(key, expectedType: .string, from: plistPath).run()` |
| Call App Store Connect | `context.appStoreConnect`, or a package service given `context.ascCredentials`, inside `mappingASCErrors { }` |

## Reference docs

- [`docs/agent-index.md`](docs/agent-index.md): sources of truth, where to start by task, change impact map, what to recommend to users
- [`docs/architecture.md`](docs/architecture.md): layers, core types, CLI commands, exit codes
- [`docs/configuration-reference.md`](docs/configuration-reference.md): every Shipfile key and env var
- [`docs/features.md`](docs/features.md): feature and command catalog
- [`docs/testing.md`](docs/testing.md): testing strategy, test workflow contracts, real-project verification
- [`docs/security.md`](docs/security.md), [`docs/ci-setup.md`](docs/ci-setup.md), [`docs/plugin-development.md`](docs/plugin-development.md), [`docs/walkthrough.md`](docs/walkthrough.md), [`docs/react-native-quickstart.md`](docs/react-native-quickstart.md)

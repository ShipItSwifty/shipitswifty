# Core Concepts

Understand the action model, workflows, registry, and configuration resolution.

## Overview

ShipItKit is built around three composable abstractions: **Actions**, **Workflows**, and the **ActionRegistry**. Together they let you define, compose, and execute release workflows declaratively.

## Actions

An `Action` is the smallest unit of work — a single step like `build`, `archive`, or `testflight`. Every action conforms to the ``Action`` protocol:

```swift
public protocol Action: Sendable {
    associatedtype Options: Sendable
    associatedtype Result: Sendable

    var name: String { get }

    func run(with options: Options, context: ActionContext) async throws -> Result

    static func descriptor(for action: Self) -> ActionDescriptor
}
```

Actions are **self-contained**: they receive all runtime context via ``ActionContext`` (shell executor, logger, resolved config, ASC client) and return a typed `Result`. They never access globals.

### ActionDescriptor

Because `Action` has associated types, it can't be stored in a heterogeneous collection directly. ``ActionDescriptor`` is a type-erased wrapper that stores the action's name and an `execute` closure:

```swift
let descriptor = BuildAction.descriptor(for: BuildAction())
```

Descriptors are what you register in the ``ActionRegistry`` and what workflows look up by name.

## ActionContext

``ActionContext`` is passed to every `Action.run(...)`. It carries:

- **`shell`** — a `ShellContext` from SwiftyShell for spawning processes
- **`logger`** — structured `Logger` for the action
- **`config`** — the fully resolved ``ResolvedConfig``
- **`ascClient`** — an optional `AppStoreConnectClient` for ASC API calls

In tests, use `ActionContext.mock(executor:)` to wire a `MockExecutor` without spawning real processes.

## Workflows

A ``Workflow`` is a named, ordered sequence of ``WorkflowStep`` values. When you run a workflow, each step is executed sequentially; if any step throws, the workflow stops and propagates the error.

```swift
let workflow = Workflow("beta", steps: [
    WorkflowStep(action: "archive", options: nil),
    WorkflowStep(action: "testflight", options: .object(["groups": .array([.string("Internal QA")])])),
])

let result = try await workflow.run(context: context, registry: registry)
```

Workflows are defined in `Shipfile.yml` under the `workflows:` key and resolved at runtime via the ``ActionRegistry``.

## ActionRegistry

``ActionRegistry`` is an `actor` that maps action names to ``ActionDescriptor`` values. It serializes concurrent registration and lookup.

```swift
let registry = ActionRegistry()
try await registry.register(BuildAction.descriptor(for: BuildAction()))
try await registry.register(TestAction.descriptor(for: TestAction()))

let descriptor = await registry.descriptor(named: "build")
```

Registration is typically done once at process startup via `registerBuiltInActions(into:)`.

## Configuration Resolution

``ConfigResolver`` merges configuration from four sources in priority order:

1. **CLI flags** — highest priority
2. **Environment variables** — `SHIPIT_*` prefix
3. **Shipfile.yml** — YAML file, supports `${ENV_VAR}` expansion
4. **Built-in defaults** — lowest priority

The result is a ``ResolvedConfig`` struct that actions read from. This means actions never parse CLI flags or YAML themselves — they only see clean, typed values.

## Build systems vs. target platforms

``Platform`` and ``BuildSystem`` are deliberately separate axes. ``Platform`` (`.ios` / `.android`) selects which side of the distribution pipeline runs. ``BuildSystem`` (`.native` / `.flutter` / `.reactNative` / `.kmp`) selects *how* the native artifact is compiled before that pipeline kicks in.

Concretely:

- A native iOS app is `Platform.ios` + `BuildSystem.native`.
- A Kotlin Multiplatform project producing both `.ipa` and `.aab` is `BuildSystem.kmp` on both platforms.
- Distribution actions (``SignAction``, ``ArchiveAction``, ``TestFlightAction``, ``PlayStoreAction``, ``UploadAction``, ``DsymAction``) read artifact paths and are unchanged across build systems. Only ``BuildAction`` and ``TestAction`` dispatch on ``BuildSystem``.

Set `ios.build_system:` / `android.build_system:` in `Shipfile.yml` or override via `SHIPIT_IOS__BUILD_SYSTEM` / `SHIPIT_ANDROID__BUILD_SYSTEM`. When unset, ``BuildSystem/autoDetect(in:fileManager:)`` infers the value from project files. See <doc:KMPIntegration> for the worked KMP example.

```swift
let resolver = ConfigResolver()
let config = try await resolver.resolve(
    cliOptions: CLIOptions(scheme: "MyApp", ci: true),
    shipfilePath: "./Shipfile.yml"
)
// config.appScheme == "MyApp"
// config.buildConfiguration == "Release" (default)
```

## Error Handling

All ShipItKit errors are ``ShipItError`` values, which carry structured context and an ``ShipItError/exitCode`` for use in CLI tools:

```swift
do {
    try await BuildAction().run(with: options, context: context)
} catch let error as ShipItError {
    logger.error("Build failed: \(error.localizedDescription)")
    throw ExitCode(error.exitCode)
}
```

## Output Formats

Actions return typed results that can be serialized by ``JSONReporter`` into ``ActionResultEnvelope`` values:

```swift
let envelope = ActionResultEnvelope(
    action: "build",
    status: "success",
    payload: .object(["scheme": .string("MyApp")])
)
let json = try JSONReporter().encode(envelope)
```

The CLI uses `HumanFormatter` for `--output human` (default) and `JSONReporter` for `--output json`. Human output supports `--color auto|always|never` and `--no-color`, while JSON output stays uncolored for downstream tooling.

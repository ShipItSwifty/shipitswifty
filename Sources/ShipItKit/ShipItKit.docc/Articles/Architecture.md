# Architecture

How ShipItKit composes actions, configuration, and runtime context into a release pipeline.

## Overview

ShipItKit is built around a small set of orthogonal concepts. Each layer is independently testable, has one job, and never reaches across module boundaries.

```
┌─────────────────────────────────────────────────────────┐
│  Sources of intent                                      │
│  CLI flags  │  SHIPIT_* env vars  │  Shipfile.yml       │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   ConfigResolver     │  (priority merge)
              └──────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │    ResolvedConfig    │  (flat, typed, Sendable)
              └──────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │    ActionContext     │  shell · logger · ASC · Play
              └──────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  ActionRegistry (actor)                                 │
│  built-in actions  +  plugin actions  +  composites     │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │    Workflow.run      │  sequential, fail-fast
              └──────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ ActionResultEnvelope │  human or JSON output
              └──────────────────────┘
```

## Layer responsibilities

### Configuration layer

``ConfigResolver`` is the only thing that reads YAML, environment variables, or CLI input. It produces a ``ResolvedConfig`` — a flat, fully-typed `Sendable` struct. Actions never parse YAML or look at `ProcessInfo` themselves.

Priority order, highest wins:

1. CLI flags
2. `SHIPIT_*` and tool-specific env vars (`ASC_*`, `GOOGLE_PLAY_*`)
3. `Shipfile.yml` (with `${ENV_VAR}` expansion)
4. Built-in defaults

See <doc:ConfigurationReference> for every key.

### Runtime context layer

``ActionContext`` packages everything an action needs to execute:

- **`shell`** — a SwiftyShell `ShellContext` for spawning processes
- **`logger`** — a structured `Logger` scoped to the operation
- **`config`** — the merged ``ResolvedConfig`` (includes ``ResolvedConfig/iosBuildSystem`` and ``ResolvedConfig/androidBuildSystem``)
- **`appStoreConnect`** — an ``AppStoreConnectClient`` (always non-nil; only fails when actually used without credentials)
- **`googlePlay`** — an optional ``GooglePlayClient`` (Android)
- **`platform`** — ``Platform`` (`.ios` or `.android`)

For tests, ``ActionContext/mock(executor:versioningSource:platform:)`` wires up a `MockExecutor` so no real processes spawn. See <doc:TestingWithMocks>.

#### Platform × BuildSystem orthogonality

``Platform`` and ``BuildSystem`` are independent axes. ``Platform`` selects the distribution pipeline (iOS vs Android); ``BuildSystem`` selects how the native artifact is compiled (`native`, `kmp`, `flutter` 🚧, `react_native` 🚧). ``BuildAction``, ``ArchiveAction``, and ``TestAction`` dispatch on ``BuildSystem`` because they invoke compile/test tools. Later actions (``SignAction``, ``ExportAction``, ``TestFlightAction``, ``PlayStoreAction``, ``UploadAction``, ``DsymAction``, and ``FrameAction``) consume artifact paths and stay unchanged across build systems. See <doc:KMPIntegration>.

### Action model

``Action`` is a `Sendable` protocol with two associated `Codable & Sendable` types — `Options` and `Result`. Implementations are pure: they read from `Options` and `ActionContext`, and return a typed `Result`.

```swift
public protocol Action: Sendable {
    associatedtype Options: Codable & Sendable
    associatedtype Result: Codable & Sendable
    static var name: String { get }
    static var description: String { get }
    func run(with options: Options, context: ActionContext) async throws -> Result
}
```

The protocol extension provides ``Action/descriptor(for:optionSchema:)`` for free, which produces a type-erased ``ActionDescriptor`` suitable for storage in ``ActionRegistry``.

### Registry & workflow runtime

``ActionRegistry`` is an `actor` that maps action names to descriptors. Built-in actions register at process start; plugins register through ``PluginRegistry``; user-defined composite actions register from `Shipfile.custom_actions`.

``Workflow`` is just a name plus an ordered array of ``WorkflowStep`` values. Each step looks up its action by name, decodes the step's `options` JSON into the action's `Options` type, and invokes `run(with:context:)`. If any step throws, the workflow stops and propagates the error.

### Output layer

Every action returns an ``ActionResultEnvelope``:

```swift
public struct ActionResultEnvelope: Codable, Sendable {
    public let action: String
    public let status: String   // "success" | "failure" | "dry_run"
    public let payload: JSONValue?
}
```

The CLI renders this either through `HumanFormatter` or ``JSONReporter``. JSON output is stable, machine-readable, and never colorised — see <doc:OutputFormats>.

## Hard rules

These are enforced by the codebase and reviewed for in every PR:

1. **All shell execution goes through SwiftyShell.** Never `Foundation.Process` directly. Use typed wrappers such as `XcodeBuild`, `Gradle`, ``Xcrun``, and `Adb`.
2. **All ASC API calls go through ``AppStoreConnectClient``.** No raw `URLSession` to Apple endpoints anywhere.
3. **All public types are `Sendable`.** Swift 6 strict concurrency throughout.
4. **All async work uses structured concurrency.** `async let`, `TaskGroup`. Never `Task.detached` for production work.
5. **Actions read only from `Options` and `ActionContext`.** No singletons, no global mutable state, no hidden caches.

## Source layout

```
Sources/
  XcodeBuildKit/      Typed xcodebuild builder, xcode-select, destination discovery
  GradleKit/          Typed Gradle, adb, emulator, and bundletool wrappers
  XcodeGenKit/        Typed xcodegen builder
  ShipItKit/
    Actions/          One file per Action type
    AppStoreConnect/  Client, JWT, upload service, models
    GooglePlay/       Client, upload service, models, JWT
    ReExports/        Re-exports XcodeBuildKit, GradleKit, and XcodeGenKit
    Xcrun/            xcrun + simctl wrappers
    CodeSigning/      Keychain, certs, profiles, vault
    Config/           Shipfile model, ConfigResolver, Platform
    Introspection/    ProjectInspector, schema, AISession types/builder, validator
    Plugin/           Action protocol, registries, plugin protocol
    Versioning/       VersionBumper, BuildNumberSource, ProjectSpecVersionSource
    Notifications/    Slack/Teams/Discord/webhook/macOS notifications
    Utilities/        ShipItError, RetryPolicy, JSONValue, JSONReporter
  CLI/
    Commands/         One file per `shipit` subcommand
    Formatters/       Human and JSON formatters
    ShipItCLI.swift   `@main` entry + GlobalOptions mixin
```

## See also

- <doc:CoreConcepts>
- <doc:Workflows>
- ``Action``
- ``ActionContext``
- ``ActionRegistry``
- ``ConfigResolver``

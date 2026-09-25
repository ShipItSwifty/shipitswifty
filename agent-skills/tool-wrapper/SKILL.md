---
name: tool-wrapper
description: Add or extend a typed command wrapper in ShipItSwifty's reusable tool libraries — GradleKit (Gradle, Adb, Bundletool, Emulator), XcodeBuildKit (xcodebuild, xcode-select), AndroidCLIKit (Google's `android` CLI), XcodeGenKit. Use when a ShipItKit action needs a flag, subcommand, or task name the wrapper does not model yet, or when a wrapper's argv construction looks wrong.
---

# Add or extend a tool wrapper

These libraries are the shared components. They depend only on SwiftyShell and Foundation and
are consumed independently of ShipItKit, so keep them free of ShipItKit concepts.

## Pattern

Every wrapper is an immutable `RunnableCommandFamily`:

```swift
public struct Tool: RunnableCommandFamily {
    public let config: ToolConfiguration
    public let stdoutDestination: OutputDestination
    public let stderrDestination: OutputDestination
    public let arguments: [String]
    public var context: ShellContext { config.context }

    /// `tool sub --flag=<value>` — What it does.
    public func sub(value: String) -> Self { copy(arguments: ["sub", "--flag=\(value)"]) }

    public func command() -> Command {        // pure: no I/O besides locating the executable
        config.apply(to: Command("tool").args(arguments).stdout(stdoutDestination).stderr(stderrDestination))
    }
}
```

- Builders return copies via a private `copy(...)`; optional properties use `String?? = .none` so
  callers can reset them to `nil`.
- Add parameters with defaults to an existing builder rather than a second overload that is also
  callable with only defaults — two such overloads make the short call ambiguous. When a typed
  variant is needed, give it a required, distinct label (e.g. `buildApks(bundle:output:signing:)`).
- Argument placement must match the tool. Gradle: global `GradleFlag`s precede tasks; task options
  (`--tests`) follow their task via `GradleTask.filteringTests(_:)` / `appendingOptions(_:)`.
  xcodebuild: build actions (`build`, `test`, `build-for-testing`, …) come last.
- Secrets: prefer file/env sources (`BundletoolPassword.file`) over argv, which other users can see.
- Executables: honour an explicit `executablePath`, then SDK environment variables from
  `context.environment` (e.g. `ANDROID_HOME/emulator/emulator`), then `PATH`.
- `#if os(macOS)` only when Apple frameworks are required, so Linux can build and test the file.
- Split into `Tool+Family.swift` extensions once one file mixes unrelated command families.

## Documentation

- DocC on every public symbol, starting with the exact command line in backticks.
- Mark device- or machine-mutating commands **Mutating**.
- A `## Usage` block on the type.
- Update the wrapper table under "Standalone tool libraries" in `docs/features.md`.

## Tests

In `Tests/<Library>Tests/`, assert the **entire** argv (`command().arguments == [...]`), not just
`contains`, and test ordering-sensitive cases explicitly. Pure helpers (name builders,
executable resolution) take injected inputs (`environment:`, `fileExists:`) so they are testable
without touching the machine.

## Wire it up

Replace any ShipItKit call site that built the same arguments by hand
(`grep -rn '\.custom(' Sources/ShipItKit`, `grep -rn 'GradleTask(name:' Sources/ShipItKit`), then
run the ShipItKit tests for the affected actions.

# Plugin Development

> **DocC mirror:** Also available as the `WritingPlugins` article and tutorial chapter 3 ("Build a Plugin") in the `ShipItKit` DocC archive. Canonical online version (coming soon): [shipitswifty.tools/docs/plugins](https://shipitswifty.tools/docs/plugins).

Extend ShipItSwifty with custom actions.

## Overview

The plugin system lets you add custom release steps without modifying the ShipItSwifty core. In v1, plugins are **statically linked** Swift packages — you add them to your `Package.swift`, register them at startup, and invoke them from `Shipfile.yml` workflows like any built-in action.

This guide walks through two complete, production-grade examples:

1. **`build-timing`** — wraps another registered action (`build`, `archive`, `test`, …) and records its wall-clock duration to a JSON log file. Useful for spotting CI build-time regressions.
2. **`copy-artifacts`** — copies built artifacts (`.ipa`, `.aab`, `.app`, dSYMs) to a versioned destination directory after `archive` / `export` finishes. Useful for shaping CI output into a stable layout.

All code in this guide is verified to compile against the public `ShipItKit` API.

## Package layout

Create a Swift package depending on `ShipItKit`:

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExamplePlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ExamplePlugin", targets: ["ExamplePlugin"])
    ],
    dependencies: [
        // Replace with the version / branch / path you want to track.
        .package(url: "https://github.com/shipitswifty/shipitswifty", branch: "main")
    ],
    targets: [
        .target(
            name: "ExamplePlugin",
            dependencies: [
                .product(name: "ShipItKit", package: "shipitswifty")
            ]
        ),
        .testTarget(
            name: "ExamplePluginTests",
            dependencies: ["ExamplePlugin"]
        )
    ]
)
```

## The `Action` protocol

Every action conforms to ``Action``:

```swift
public protocol Action: Sendable {
    associatedtype Options: Codable & Sendable
    associatedtype Result: Codable & Sendable

    static var name: String { get }
    static var description: String { get }

    func run(with options: Options, context: ActionContext) async throws -> Result
}
```

Key points:

- `name` and `description` are **`static`** — one identifier per action type.
- `Options` and `Result` must both be **`Codable & Sendable`**. ShipItKit decodes `Options` from `Shipfile.yml` automatically (snake-case YAML keys are mapped to camelCase Swift properties).
- `Action` is `Sendable`; all stored properties must therefore be `Sendable` too.
- The protocol provides `static func descriptor(for: Self, optionSchema: [SchemaField] = [])` automatically — you almost never need to write one by hand.

The `ActionContext` you receive in `run(with:context:)` exposes:

| Property | Type | Description |
|---|---|---|
| `shell` | `ShellContext` | SwiftyShell context for spawning subprocesses |
| `logger` | `Logger` | OSLog logger scoped to your action |
| `config` | `ResolvedConfig` | Final merged Shipfile + env + CLI configuration |
| `appStoreConnect` | `AppStoreConnectClient` | App Store Connect REST client |
| `googlePlay` | `GooglePlayClient?` | Google Play client (Android only; `nil` otherwise) |
| `platform` | `Platform` | `.ios` or `.android` |

To run a shell command, use the SwiftyShell `Command` API (never `Foundation.Process` directly):

```swift
import SwiftyShell

let output = try await Command("git", "status", "--porcelain").run(in: context.shell)
context.logger.info("git status: \(output.stdout)")
```

For `xcodebuild` and `gradle`, prefer the typed `XcodeBuild` / `Gradle` fluent wrappers from ShipItKit — they handle quoting, options, and build settings safely.

## Example 1: `BuildTimingAction`

This action wraps another registered action and records how long it takes. It demonstrates:

- Looking up another action via `ActionRegistry`
- Forwarding free-form options as `JSONValue`
- Persisting structured output to disk
- Re-throwing the wrapped action's error after still recording the timing

```swift
// Sources/ExamplePlugin/BuildTimingAction.swift
import Foundation
import OSLog
import ShipItKit

public struct BuildTimingAction: Action {
    public static let name = "build-timing"
    public static let description = "Wrap another action and record its wall-clock duration to a JSON log."

    public struct Options: Codable, Sendable {
        /// Name of the registered action to wrap (e.g. `"build"`, `"archive"`, `"test"`).
        public var wraps: String
        /// Options forwarded to the wrapped action. Free-form JSON so it can mirror any wrapped action's schema.
        public var options: JSONValue?
        /// File path where timing entries are appended. Defaults to `./build/timings.json`.
        public var logPath: String?
        /// Optional human label included in the log entry.
        public var label: String?

        public init(
            wraps: String,
            options: JSONValue? = nil,
            logPath: String? = nil,
            label: String? = nil
        ) {
            self.wraps = wraps
            self.options = options
            self.logPath = logPath
            self.label = label
        }
    }

    public struct Result: Codable, Sendable {
        public var wrapped: String
        public var durationSeconds: Double
        public var logPath: String
        public var status: String

        public init(wrapped: String, durationSeconds: Double, logPath: String, status: String) {
            self.wrapped = wrapped
            self.durationSeconds = durationSeconds
            self.logPath = logPath
            self.status = status
        }
    }

    /// The registry the wrapped action is looked up in.
    /// Pass the same `ActionRegistry` you populated with built-in actions.
    public let registry: ActionRegistry

    public init(registry: ActionRegistry) {
        self.registry = registry
    }

    private let logger = Logger.forType(subsystem: "ExamplePlugin", BuildTimingAction.self)

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard let descriptor = await registry.descriptor(named: options.wraps) else {
            throw ShipItError.invalidConfiguration(
                reason: "build-timing: no action named '\(options.wraps)' is registered."
            )
        }

        let logPath = options.logPath ?? "./build/timings.json"
        let label = options.label ?? options.wraps
        let start = Date()

        logger.info("Starting wrapped action '\(options.wraps)' (label=\(label))")
        var status = "success"
        var thrown: Error?
        do {
            _ = try await descriptor.runJSON(options.options, context)
        } catch {
            status = "failure"
            thrown = error
        }
        let duration = Date().timeIntervalSince(start)
        logger.info("Wrapped action '\(options.wraps)' finished in \(String(format: "%.2f", duration))s (\(status))")

        try appendTimingEntry(
            to: logPath,
            label: label,
            wrapped: options.wraps,
            duration: duration,
            status: status
        )

        if let thrown { throw thrown }

        return Result(
            wrapped: options.wraps,
            durationSeconds: duration,
            logPath: logPath,
            status: status
        )
    }

    private func appendTimingEntry(
        to path: String,
        label: String,
        wrapped: String,
        duration: TimeInterval,
        status: String
    ) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var entries: [[String: JSONValue]] = []
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode([JSONValue].self, from: data) {
            entries = existing.compactMap(\.objectValue)
        }

        let isoTimestamp = ISO8601DateFormatter().string(from: Date())
        entries.append([
            "timestamp": .string(isoTimestamp),
            "label": .string(label),
            "wrapped": .string(wrapped),
            "durationSeconds": .double(duration),
            "status": .string(status)
        ])

        let array = JSONValue.array(entries.map { .object($0) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(array)
        try data.write(to: url, options: .atomic)
    }
}
```

Use it from `Shipfile.yml`:

```yaml
workflows:
  beta:
    - action: build-timing
      options:
        wraps: build
        label: "Beta clean build"
        log_path: ./build/timings.json
        options:
          scheme: MyApp
          configuration: Release
          clean: true
    - action: archive
    - action: testflight
```

## Example 2: `CopyArtifactsAction`

This action copies built artifacts into a versioned destination directory, supporting `{bundle_id}` and `{timestamp}` placeholders so paths remain stable per-run. It demonstrates:

- Path templating from values in `ResolvedConfig`
- Clean error handling for missing inputs and accidental overwrites
- An optional file-extension allow-list

```swift
// Sources/ExamplePlugin/CopyArtifactsAction.swift
import Foundation
import OSLog
import ShipItKit

public struct CopyArtifactsAction: Action {
    public static let name = "copy-artifacts"
    public static let description = "Copy built artifacts (.ipa, .aab, .app, dSYMs) to a versioned destination directory."

    public struct Options: Codable, Sendable {
        /// One or more source files or directories to copy.
        public var sources: [String]
        /// Destination directory. Supports `{bundle_id}` and `{timestamp}` placeholders.
        public var destination: String
        /// Overwrite existing files in the destination. Default `false` — fail instead.
        public var overwrite: Bool?
        /// Only copy files whose extensions match this allow-list (e.g. `["ipa", "aab", "dSYM"]`).
        public var includeExtensions: [String]?

        public init(
            sources: [String],
            destination: String,
            overwrite: Bool? = nil,
            includeExtensions: [String]? = nil
        ) {
            self.sources = sources
            self.destination = destination
            self.overwrite = overwrite
            self.includeExtensions = includeExtensions
        }
    }

    public struct Result: Codable, Sendable {
        public var destination: String
        public var copied: [String]
        public var skipped: [String]

        public init(destination: String, copied: [String], skipped: [String]) {
            self.destination = destination
            self.copied = copied
            self.skipped = skipped
        }
    }

    public init() {}

    private let logger = Logger.forType(subsystem: "ExamplePlugin", CopyArtifactsAction.self)

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let destination = expand(options.destination, context: context)
        let destURL = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

        let allowExtensions = options.includeExtensions.map { Set($0.map { $0.lowercased() }) }
        let overwrite = options.overwrite ?? false

        var copied: [String] = []
        var skipped: [String] = []

        for source in options.sources {
            let sourceURL = URL(fileURLWithPath: source)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                logger.error("copy-artifacts: source does not exist: \(source)")
                throw ShipItError.invalidConfiguration(
                    reason: "copy-artifacts: source '\(source)' does not exist"
                )
            }

            if let allow = allowExtensions {
                let ext = sourceURL.pathExtension.lowercased()
                guard allow.contains(ext) else {
                    skipped.append(source)
                    continue
                }
            }

            let target = destURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                if overwrite {
                    try FileManager.default.removeItem(at: target)
                } else {
                    throw ShipItError.invalidConfiguration(
                        reason: "copy-artifacts: '\(target.path)' already exists; pass overwrite: true to replace it"
                    )
                }
            }

            try FileManager.default.copyItem(at: sourceURL, to: target)
            logger.info("Copied \(sourceURL.lastPathComponent) -> \(target.path)")
            copied.append(target.path)
        }

        return Result(destination: destination, copied: copied, skipped: skipped)
    }

    private func expand(_ template: String, context: ActionContext) -> String {
        let bundleID = context.config.bundleID ?? "app"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return template
            .replacingOccurrences(of: "{bundle_id}", with: bundleID)
            .replacingOccurrences(of: "{timestamp}", with: timestamp)
    }
}
```

Use it from `Shipfile.yml`:

```yaml
workflows:
  beta:
    - action: archive
    - action: export
    - action: copy-artifacts
      options:
        sources:
          - ./build/MyApp.xcarchive
          - ./build/export/MyApp.ipa
        destination: ./release-artifacts/{bundle_id}/{timestamp}
        overwrite: true
        include_extensions: [ipa, xcarchive]
```

## Bundling into a `ShipItPlugin`

`BuildTimingAction` needs the `ActionRegistry` to look up the wrapped action, so this plugin exposes a factory rather than a static `actions` list:

```swift
// Sources/ExamplePlugin/ExamplePlugin.swift
import ShipItKit

public enum ExamplePlugin {
    public static let name = "example"
    public static let description = "BuildTimingAction + CopyArtifactsAction."

    /// Returns descriptors for both actions, bound to the given registry.
    public static func actions(registry: ActionRegistry) -> [ActionDescriptor] {
        [
            BuildTimingAction.descriptor(for: BuildTimingAction(registry: registry)),
            CopyArtifactsAction.descriptor(for: CopyArtifactsAction())
        ]
    }
}
```

For self-contained plugins that don't need the registry, you can conform to `ShipItPlugin` directly:

```swift
public struct StaticExamplePlugin: ShipItPlugin {
    public static let name = "example-static"
    public static let description = "Just CopyArtifactsAction."
    public static let actions: [ActionDescriptor] = [
        CopyArtifactsAction.descriptor(for: CopyArtifactsAction())
    ]
}
```

## Registering at startup

Register your plugin's actions into the same `ActionRegistry` the CLI builds from its built-in actions:

```swift
import ShipItKit
import ExamplePlugin

let registry = ActionRegistry()
try await registerBuiltInActions(into: registry)        // built-in: build, test, archive, …

// Factory-style registration (for actions that need the registry)
for descriptor in ExamplePlugin.actions(registry: registry) {
    try await registry.register(descriptor)
}

// Static-style registration via `ShipItPlugin`
let plugins = PluginRegistry()
await plugins.register(StaticExamplePlugin.self)
try await plugins.registerAll(into: registry)
```

After registration, `shipit run <workflow>` resolves your action names from `Shipfile.yml` exactly like the built-ins.

## Testing

Use `ActionContext.mock(executor:)` to get a fully-formed context without spawning real processes. The factory requires a `MockExecutor` from `SwiftyShell` (it has no zero-argument overload):

```swift
import Foundation
import Testing
import SwiftyShell
import ShipItKit
@testable import ExamplePlugin

@Suite("CopyArtifactsAction")
struct CopyArtifactsActionTests {
    @Test("Copies a single file to the destination directory")
    func copiesSingleFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-copy-artifacts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sourceDir = tmp.appendingPathComponent("src")
        let destDir = tmp.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let source = sourceDir.appendingPathComponent("MyApp.ipa")
        try Data("fake-ipa".utf8).write(to: source)

        let context = ActionContext.mock(
            executor: MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        )

        let result = try await CopyArtifactsAction().run(
            with: .init(
                sources: [source.path],
                destination: destDir.path,
                overwrite: true
            ),
            context: context
        )

        #expect(result.copied.count == 1)
        #expect(result.skipped.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("MyApp.ipa").path))
    }
}
```

## `JSONValue` reference

When you accept free-form, dynamically-typed options (as `BuildTimingAction` does for `options.options`), use `JSONValue` accessors and pattern matching:

| Accessor | Returns |
|---|---|
| `.stringValue` | `String?` |
| `.intValue` | `Int?` |
| `.doubleValue` | `Double?` |
| `.boolValue` | `Bool?` |
| `.arrayValue` | `[JSONValue]?` |
| `.objectValue` | `[String: JSONValue]?` |
| `.isNull` | `Bool` |

Construct values via the `case` constructors or the literal conformances (`ExpressibleByStringLiteral`, `ExpressibleByDictionaryLiteral`, `ExpressibleByArrayLiteral`, etc.):

```swift
let payload: JSONValue = .object([
    "scheme": "MyApp",            // string literal
    "retries": 3,                 // integer literal
    "destinations": ["iPhone 15"] // array literal
])

let scheme = payload.objectValue?["scheme"]?.stringValue   // "MyApp"
```

For typed `Options` structs (the recommended approach for action-specific configuration), let `JSONDecoder` do the work via `Codable`. ShipItKit configures the decoder with `keyDecodingStrategy = .convertFromSnakeCase`, so `log_path: …` in YAML maps to `var logPath: String?` in Swift.

## Naming conventions

- Action names should be lowercase with hyphens: `build-timing`, `copy-artifacts`, `slack-post`.
- Plugin names should be lowercase: `example`, `analytics`, `custom-signing`.
- Don't collide with built-in action names. Current built-ins:

  `build`, `test`, `coverage`, `archive`, `export`, `lint`, `play-store`, `validate-bundle`, `sign`, `upload`, `testflight`, `snapshot`, `frame`, `version`, `metadata`, `precheck`, `validate-archive`, `provision`, `notify`, `git`, `dsym`, `generate-project`.

  `shipit validate yml` will reject any custom action whose name collides with these.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Type 'MyAction' does not conform to protocol 'Action'` | `Options` or `Result` is missing `Codable` (only `Sendable` is not enough). |
| `No action named 'foo' is registered` at runtime | The plugin wasn't registered into the same `ActionRegistry` the workflow runner uses. Register before calling `Workflow.run(...)`. |
| YAML `log_path: ./build/timings.json` produces `nil` in `Options.logPath` | The property name doesn't match the snake-case → camelCase mapping. The decoder uses `.convertFromSnakeCase`; double-check spelling. |
| Tests fail to compile referencing `ActionContext.mock()` | The factory requires `executor:` — pass a `MockExecutor` from `SwiftyShell`. |

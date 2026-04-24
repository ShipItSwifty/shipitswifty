# Writing Plugins

Extend ShipItKit with custom actions using the plugin system.

## Overview

ShipItKit's plugin system lets you add custom actions without modifying the core library. In v1, plugins are **statically linked** Swift packages — you add them to `Package.swift` and register them at startup. Runtime dylib loading is out of scope.

This article covers the protocol contract; for two complete, end-to-end runnable examples (`build-timing` that wraps another action, and `copy-artifacts` that copies built `.ipa` / `.aab` / dSYMs to a versioned directory), see [`docs/plugin-development.md`](https://github.com/shipitswifty/shipitswifty/blob/main/docs/plugin-development.md) in the repository.

## Creating a plugin

### 1. Create a Swift package

Create a new package (or add a target to an existing one) that depends on `ShipItKit`:

```swift
// Package.swift
.package(url: "https://github.com/shipitswifty/shipitswifty", branch: "main"),

.target(
    name: "MyPlugin",
    dependencies: [
        .product(name: "ShipItKit", package: "shipitswifty")
    ]
)
```

### 2. Define your action

Conform to ``Action``:

```swift
import Foundation
import OSLog
import ShipItKit

public struct TrackReleaseAction: Action {
    public static let name = "track-release"
    public static let description = "POST a release event to an analytics endpoint."

    public struct Options: Codable, Sendable {
        public var version: String
        public var channel: String?

        public init(version: String, channel: String? = nil) {
            self.version = version
            self.channel = channel
        }
    }

    public struct Result: Codable, Sendable {
        public var eventId: String

        public init(eventId: String) { self.eventId = eventId }
    }

    public init() {}

    private let logger = Logger.forType(subsystem: "MyPlugin", TrackReleaseAction.self)

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let channel = options.channel ?? "production"
        logger.info("Tracking release v\(options.version) to \(channel)")
        // … POST to your analytics endpoint here.
        return Result(eventId: "evt_123")
    }
}
```

Key requirements enforced by the protocol:

- ``Action/name`` and ``Action/description`` are **`static`** properties.
- `Options` and `Result` must be **`Codable & Sendable`**. ShipItKit decodes `Options` from `Shipfile.yml` automatically (snake-case YAML keys → camelCase Swift properties).
- The protocol provides ``Action/descriptor(for:optionSchema:)`` automatically — you do not need to write one by hand.

### 3. Bundle into a `ShipItPlugin`

```swift
public struct MyAnalyticsPlugin: ShipItPlugin {
    public static let name = "analytics"
    public static let description = "Analytics integration for release tracking."
    public static let actions: [ActionDescriptor] = [
        TrackReleaseAction.descriptor(for: TrackReleaseAction())
    ]
}
```

### 4. Register at startup

```swift
import ShipItKit
import MyPlugin

let registry = ActionRegistry()
try await registerBuiltInActions(into: registry)

let plugins = PluginRegistry()
await plugins.register(MyAnalyticsPlugin.self)
try await plugins.registerAll(into: registry)
```

### 5. Use in a workflow

```yaml
workflows:
  release:
    - action: archive
    - action: upload
    - action: track-release
      options:
        version: "2.1.0"
        channel: production
```

## ActionDescriptor in depth

``ActionDescriptor`` stores a type-erased `runJSON` closure that receives:

- `options: JSONValue?` — the step's `options` dict from the Shipfile, or `nil`
- `context: ActionContext` — shell, logger, config, App Store Connect / Google Play clients

For typed `Options`, the auto-generated descriptor handles `JSONValue → Options` decoding via `Codable`. For free-form options, use ``JSONValue`` accessors (`stringValue`, `intValue`, `doubleValue`, `boolValue`, `arrayValue`, `objectValue`, `isNull`):

```swift
let scheme = options?.objectValue?["scheme"]?.stringValue ?? "MyApp"
let retries = options?.objectValue?["retries"]?.intValue ?? 3
```

## Testing your plugin

Use ``ActionContext/mock(executor:versioningSource:platform:)`` to build a test context without spawning real processes. The factory requires a `MockExecutor` from `SwiftyShell` — there is no zero-argument overload:

```swift
import Foundation
import Testing
import SwiftyShell
import ShipItKit
@testable import MyPlugin

@Test func trackReleaseReturnsEventID() async throws {
    let context = ActionContext.mock(
        executor: MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
    )
    let action = TrackReleaseAction()
    let result = try await action.run(
        with: .init(version: "1.0", channel: "beta"),
        context: context
    )
    #expect(result.eventId.isEmpty == false)
}
```

## See also

- ``Action``
- ``ActionDescriptor``
- ``ActionRegistry``
- ``ActionContext``
- ``ShipItPlugin``
- ``PluginRegistry``
- ``JSONValue``

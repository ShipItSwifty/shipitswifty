# Writing Plugins

Extend ShipItKit with custom actions using the plugin system.

## Overview

ShipItKit's plugin system lets you add custom actions without modifying the core library. In v1, plugins are **statically linked** Swift packages — you add them to `Package.swift` and register them at startup. Runtime dylib loading is out of scope.

## Creating a Plugin

### 1. Create a Swift package

Create a new package (or add a target to an existing one) that depends on `ShipItKit`:

```swift
// Package.swift
.package(path: "../ShipItSwifty"),

.target(
    name: "MyPlugin",
    dependencies: [
        .product(name: "ShipItKit", package: "ShipItSwifty")
    ]
)
```

### 2. Define your Action

Conform to ``Action`` protocol:

```swift
import ShipItKit

public struct TrackReleaseAction: Action {
    public struct Options: Sendable {
        public let version: String
        public let channel: String
    }

    public struct Result: Sendable {
        public let eventId: String
    }

    public var name: String { "track-release" }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        context.logger.info("Tracking release v\(options.version) to \(options.channel)")
        // ... call your analytics service
        return Result(eventId: "evt_123")
    }

    public static func descriptor(for action: TrackReleaseAction) -> ActionDescriptor {
        ActionDescriptor(name: action.name) { options, context in
            // Decode options from JSONValue
            let version = options?["version"]?.string ?? "unknown"
            let channel = options?["channel"]?.string ?? "production"
            let result = try await action.run(
                with: Options(version: version, channel: channel),
                context: context
            )
            return ActionResultEnvelope(
                action: action.name,
                status: "success",
                payload: .object(["eventId": .string(result.eventId)])
            )
        }
    }
}
```

### 3. Export a ShipItPlugin

```swift
import ShipItKit

public struct MyAnalyticsPlugin: ShipItPlugin {
    public static let name = "analytics"
    public static let description = "Analytics integration for release tracking"
    public static var actions: [ActionDescriptor] = [
        TrackReleaseAction.descriptor(for: TrackReleaseAction())
    ]
}
```

### 4. Register at startup

In your CLI entry point or bootstrap code:

```swift
import ShipItKit
import MyPlugin

let registry = ActionRegistry()
let plugins = PluginRegistry()
plugins.register(MyAnalyticsPlugin.self)
try await plugins.registerAll(into: registry)
```

Or add the action directly to `registerBuiltInActions(into:)` in the CLI layer.

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

## ActionDescriptor in Depth

``ActionDescriptor`` stores a type-erased `execute` closure that receives:

- `options: JSONValue?` — the step's `options` dict from the Shipfile, or `nil`
- `context: ActionContext` — shell, logger, config, ASC client

Your descriptor is responsible for decoding `JSONValue` options into your action's typed `Options` struct. Use ``JSONValue`` subscripts and type accessors:

```swift
let version = options?["version"]?.string ?? "unknown"
let retries = options?["retries"]?.int ?? 3
```

## Testing Your Plugin

Use `ActionContext.mock(executor:)` to get a test context without spawning real processes:

```swift
import XCTest
import ShipItKit

final class TrackReleaseActionTests: XCTestCase {
    func testTrackRelease() async throws {
        let context = ActionContext.mock()
        let action = TrackReleaseAction()
        let result = try await action.run(
            with: .init(version: "1.0", channel: "beta"),
            context: context
        )
        XCTAssertFalse(result.eventId.isEmpty)
    }
}
```

# Plugin Development

Extend ShipItSwifty with custom actions.

## Overview

The plugin system allows you to add custom release steps without modifying the ShipItSwifty core. Plugins are **statically linked** Swift packages — you add them to `Package.swift` and register them at startup.

## Quick Example

```swift
import ShipItKit

// 1. Define your action
public struct SlackPostAction: Action {
    public struct Options: Sendable {
        public let message: String
        public let channel: String
    }
    public struct Result: Sendable {
        public let messageId: String
    }

    public var name: String { "slack-post" }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        context.logger.info("Posting to \(options.channel): \(options.message)")
        // ... HTTP call to Slack
        return Result(messageId: "msg_123")
    }

    public static func descriptor(for action: Self) -> ActionDescriptor {
        ActionDescriptor(name: action.name) { options, context in
            let message = options?["message"]?.string ?? ""
            let channel = options?["channel"]?.string ?? "#general"
            let result = try await action.run(
                with: Options(message: message, channel: channel),
                context: context
            )
            return ActionResultEnvelope(
                action: action.name,
                status: "success",
                payload: .object(["messageId": .string(result.messageId)])
            )
        }
    }
}

// 2. Bundle into a plugin
public struct SlackPlugin: ShipItPlugin {
    public static let name = "slack"
    public static let description = "Custom Slack integration"
    public static var actions: [ActionDescriptor] = [
        SlackPostAction.descriptor(for: SlackPostAction())
    ]
}
```

## Step-by-Step

### 1. Create a package

Add a new target or package that depends on `ShipItKit`:

```swift
// In your Package.swift
.target(
    name: "MyPlugin",
    dependencies: [
        .product(name: "ShipItKit", package: "ShipItSwifty")
    ]
)
```

### 2. Implement `Action`

Conform to `Action`:

- Define typed `Options` and `Result` structs (both `Sendable`)
- Implement `run(with:context:) async throws -> Result`
- Implement `descriptor(for:)` to produce a type-erased `ActionDescriptor`

In the descriptor's closure, decode `options: JSONValue?` using subscripts:

```swift
let retries = options?["retries"]?.int ?? 3
let url = options?["url"]?.string ?? ""
let flags = options?["flags"]?.array?.compactMap { $0.string } ?? []
```

### 3. Implement `ShipItPlugin`

```swift
public struct MyPlugin: ShipItPlugin {
    public static let name = "my-plugin"
    public static let description = "Description of what this plugin provides"
    public static var actions: [ActionDescriptor] = [
        MyAction.descriptor(for: MyAction()),
        AnotherAction.descriptor(for: AnotherAction()),
    ]
}
```

### 4. Register at startup

In the CLI or your tool's bootstrap:

```swift
let registry = ActionRegistry()
let plugins = PluginRegistry()
plugins.register(MyPlugin.self)
try await plugins.registerAll(into: registry)
```

Or add the descriptor directly in `registerBuiltInActions(into:)` for CLI integration.

### 5. Use in lanes

```yaml
lanes:
  deploy:
    - action: archive
    - action: upload
    - action: slack-post
      options:
        channel: "#releases"
        message: "Uploaded to App Store!"
```

## ActionContext

Every action receives an `ActionContext` with:

| Property | Type | Description |
|---|---|---|
| `shell` | `ShellContext` | SwiftyShell executor for running subprocesses |
| `logger` | `Logger` | Scoped OSLog logger |
| `config` | `ResolvedConfig` | All resolved configuration values |
| `ascClient` | `AppStoreConnectClient?` | ASC API client (nil if credentials missing) |

Example — running a shell command:

```swift
let output = try await context.shell.run("xcodebuild", "-version")
```

## Testing Your Plugin

Use `ActionContext.mock(executor:)` to test without spawning real processes:

```swift
import Testing
import ShipItKit
@testable import MyPlugin

@Test func testSlackPost() async throws {
    let context = ActionContext.mock()
    let result = try await SlackPostAction().run(
        with: .init(message: "Hello", channel: "#test"),
        context: context
    )
    #expect(result.messageId.isEmpty == false)
}
```

## JSONValue Reference

Options passed from Shipfile lanes are decoded from `JSONValue`. Accessors:

| Accessor | Returns |
|---|---|
| `.string` | `String?` |
| `.int` | `Int?` |
| `.double` | `Double?` |
| `.bool` | `Bool?` |
| `.array` | `[JSONValue]?` |
| `.object` | `[String: JSONValue]?` |
| `["key"]` | `JSONValue?` (subscript) |

## Naming Conventions

- Action names should be lowercase with hyphens: `track-release`, `slack-post`
- Plugin names should be lowercase: `analytics`, `custom-signing`
- Avoid colliding with built-in action names: `build`, `test`, `archive`, `export`, `upload`, `testflight`, `snapshot`, `frame`, `sign`, `version`, `metadata`, `precheck`, `provision`, `notify`, `git`, `dsym`

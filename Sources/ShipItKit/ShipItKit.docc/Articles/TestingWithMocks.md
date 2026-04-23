# Testing With Mocks

Unit-test actions and plugins without spawning real processes or hitting App Store Connect.

## Overview

ShipItKit is structured so every action is testable in isolation. Two helpers do the heavy lifting:

1. ``ActionContext/mock(executor:versioningSource:platform:)`` — gives you a fully wired ``ActionContext`` with a mock shell.
2. `makeClient(responses:)` (in `Tests/ShipItKitTests/TestSupport.swift`) — produces an ``AppStoreConnectClient`` whose URLSession is fed by `MockURLProtocol`.

All tests in this project use **Swift Testing** (`@Test`, `#expect`, `#require`) — no XCTest.

## Mocking shell commands

`MockExecutor` is provided by SwiftyShell. It accepts a closure that decides what to return for any spawned command:

```swift
import Foundation
import Testing
import SwiftyShell
import ShipItKit

@Test func buildSucceedsWhenXcodebuildExitsZero() async throws {
    let executor = MockExecutor { command, _ in
        // command is the parsed Command value — assert on it if you want.
        ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)
    let result = try await BuildAction().run(
        with: .init(scheme: "Mock"),
        context: context
    )
    #expect(result.exitCode == 0)
}
```

### Asserting on the command

`MockExecutor`'s closure receives the parsed `Command` value, so you can assert on tool, args, or environment:

```swift
@Test func buildPassesSchemeToXcodebuild() async throws {
    let recorded = LockedBox<[String]>([])
    let executor = MockExecutor { command, _ in
        recorded.with { $0.append(command.executable) }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)
    _ = try? await BuildAction().run(with: .init(scheme: "MyApp"), context: context)
    #expect(recorded.value.contains("xcodebuild"))
}
```

### Simulating a failure

```swift
@Test func buildThrowsOnNonZeroExit() async throws {
    let executor = MockExecutor { _, _ in
        ShellOutput(stdout: "", stderr: "compile error", exitCode: 65)
    }
    let context = ActionContext.mock(executor: executor)
    await #expect(throws: ShipItError.self) {
        try await BuildAction().run(with: .init(scheme: "Mock"), context: context)
    }
}
```

## Mocking App Store Connect

For tests that exercise ``AppStoreConnectClient``, use `makeClient(responses:)` from `Tests/ShipItKitTests/TestSupport.swift`. It queues canned HTTP responses via `MockURLProtocol` and returns a real client — no network, no JWT roundtrip, full request/response cycle.

```swift
@Test func uploadActionPostsToBuildsEndpoint() async throws {
    let client = makeClient(responses: [
        .json(["data": ["id": "build-123"]], status: 201),
        .empty(status: 204)   // for the finalize call
    ])
    let context = ActionContext.mock(executor: MockExecutor { _, _ in
        ShellOutput(stdout: "", stderr: "", exitCode: 0)
    })
    // Inject the mocked client however the action exposes it
    // (constructor injection is preferred; see specific action docs.)
    // …
}
```

Failure paths:

```swift
let client = makeClient(responses: [
    .json(["errors": [["status": "401", "title": "Invalid token"]]], status: 401)
])
```

The client maps non-2xx responses to ``ShipItError/apiError(statusCode:body:)``.

## Mocking time and retries

``RetryPolicy`` uses `Task.sleep(for:)` between attempts. In tests you usually want to disable backoff:

```swift
let policy = RetryPolicy(maxAttempts: 3, initialDelay: .zero, multiplier: 1.0)
```

This still exercises the retry loop without slowing the suite.

## Testing composite actions

Composites resolve through the same ``ActionRegistry`` as built-ins. Build a registry with a fake action, register the composite, and execute:

```swift
let registry = ActionRegistry()
try await registry.register(FakeBuild.descriptor(for: FakeBuild()))
try await registry.registerCustomActions([
    "build_and_sign": CustomActionConfig(
        description: nil,
        parameters: [:],
        steps: [WorkflowStep(action: "build", options: nil)]
    )
])
let descriptor = await #require(registry.descriptor(named: "build_and_sign"))
_ = try await descriptor.runJSON(nil, context)
```

## Plugins

Use the same patterns. Build a context with `mock(executor:)`, run your plugin's action, and assert on the result.

```swift
@Test func trackReleaseReturnsEventID() async throws {
    let context = ActionContext.mock(
        executor: MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
    )
    let result = try await TrackReleaseAction().run(
        with: .init(version: "1.0", channel: "beta"),
        context: context
    )
    #expect(result.eventId.isEmpty == false)
}
```

## Tags & parallel execution

Tests are parallel-safe by default. Tag long-running ones so you can opt them in:

```swift
@Test(.tags(.integration))
func roundtripUploadAgainstStaging() async throws { … }
```

Then run only the fast suite:

```bash
swift test --skip-tag integration
```

## See also

- ``ActionContext/mock(executor:versioningSource:platform:)``
- ``RetryPolicy``
- ``AppStoreConnectClient``
- <doc:WritingPlugins>
- <doc:ErrorHandling>

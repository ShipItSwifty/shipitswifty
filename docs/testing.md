# ShipItSwifty — Testing Strategy

## Overview

| Module | Target Coverage |
|---|---|
| ShipItKit | ≥ 85% line coverage |
| CLI | ≥ 70% (integration tests) |

All tests use Swift Testing (`@Test`) over XCTest per project conventions.

---

## Unit tests — ShipItKit

Use `MockExecutor` from SwiftyShell to stub all shell calls. Use `ActionContext.mock(executor:)` to wire a fully-formed context without spawning real processes.

```swift
import Testing
import SwiftyShell
@testable import ShipItKit

@Test("BuildAction invokes xcodebuild with correct arguments")
func buildActionArgs() async throws {
    var capturedCommands: [String] = []
    let executor = MockExecutor { command, _ in
        capturedCommands.append(command.description)
        return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)
    let options = BuildAction.Options(scheme: "MyApp", configuration: .release)

    _ = try await BuildAction().run(with: options, context: context)

    #expect(capturedCommands.first?.contains("-scheme MyApp") == true)
    #expect(capturedCommands.first?.contains("-configuration Release") == true)
}
```

---

## HTTP mocking — ASC API tests

Use `makeClient(responses:)` + `MockURLProtocol` from `Tests/ShipItKitTests/TestSupport.swift` to queue canned HTTP responses:

```swift
@Test("TestFlightAction uploads IPA and waits for processing")
func testFlightUpload() async throws {
    let client = makeClient(responses: [
        .success(data: appsResponseJSON),
        .success(data: buildsResponseJSON),
    ])
    let context = ActionContext.mock(executor: MockExecutor.empty, ascClient: client)
    // ...
}
```

---

## CLI integration tests

```swift
@Test("shipit build --scheme MyApp prints a dry-run message")
func cliBuildDryRun() async throws {
    let result = try await Command("swift", "run", "shipit", "build",
                                    "--scheme", "MockApp",
                                    "--dry-run")
        .run(in: ShellContext())
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("DRY RUN"))
}
```

---

## Rules

- Every `Action` MUST have tests using `MockExecutor`
- Every CLI `Command` MUST have integration tests
- No real network calls in tests — mock `AppStoreConnectClient`
- No real shell calls in tests — use `MockExecutor`
- Test both success and error paths

---

## Running tests

```bash
# All tests with coverage
swift test --enable-code-coverage

# Filter to a single test class
swift test --filter ShipItKitTests.BuildActionTests

# Filter to a target
swift test --filter CLITests
```

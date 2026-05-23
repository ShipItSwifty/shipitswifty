# ShipItSwifty — Testing Strategy

> **DocC mirror:** Also available as the `TestingWithMocks` article in the `ShipItKit` DocC archive.

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

The integration target also includes deterministic Flutter, React Native, and KMP fixture suites. These use lightweight tool shims to validate ShipIt's command dispatch and artifact path handling for cross-platform projects without requiring a real Flutter SDK, CocoaPods, a full Kotlin toolchain, or external OSS checkout on every machine.

### External project validation

`IntegrationTests` also supports opt-in validation against real open-source Flutter and React Native projects outside the repo. Point the tests at local checkouts with environment variables:

```bash
export SHIPIT_EXTERNAL_FLUTTER_PROJECT=/tmp/flutter-samples/testing_app
export SHIPIT_EXTERNAL_RN_PROJECT=/tmp/rn-template/template
yarn --cwd "$SHIPIT_EXTERNAL_RN_PROJECT" install

swift build
swift test --filter FlutterExternalIntegrationTests
swift test --filter ReactNativeExternalIntegrationTests
```

These suites are skipped unless the paths are configured. Flutter tests also require `flutter` on `PATH`; React Native iOS tests require `pod` on `PATH`; React Native external tests expect `node_modules/` to already exist in the target checkout.

For the built-in local verification flow that covers native, Flutter, React Native, and KMP fixture artifacts end-to-end, run:

```bash
./scripts/verify-cross-platform.sh
# or:
make verify-cross-platform
```

---

## Rules

- Every `Action` MUST have tests using `MockExecutor`
- Every CLI `Command` MUST have integration tests
- No real network calls in tests — mock `AppStoreConnectClient`
- No real shell calls in tests — use `MockExecutor`
- Test both success and error paths

---

## DestinationDiscovery tests

`DestinationDiscovery` parses the text output of `xcodebuild -showdestinations`. Test the parser and sort order with a `MockExecutor`:

```swift
@Test("DestinationDiscovery parses simulator and device entries")
func destinationDiscoveryParsesOutput() async throws {
    let rawOutput = """
    Available destinations for the "MyApp" scheme:
        { platform:iOS Simulator, id:00000000-1111-2222-3333-444444444444, OS:17.0, name:iPhone 15 }
        { platform:iOS, id:AA:BB:CC:DD:EE:FF, name:My iPhone }
    """
    let executor = MockExecutor { _, _ in
        ShellOutput(stdout: rawOutput, stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)
    let destinations = try await DestinationDiscovery(context: context)
        .discover(scheme: "MyApp")

    // Simulators are sorted first, then physical devices
    #expect(destinations.count == 2)
    #expect(destinations[0].platform == "iOS Simulator")
    #expect(destinations[1].platform == "iOS")
}

@Test("DestinationDiscovery returns empty array when xcodebuild emits no destinations")
func destinationDiscoveryEmpty() async throws {
    let executor = MockExecutor { _, _ in
        ShellOutput(stdout: "Available destinations for ...\n", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)
    let destinations = try await DestinationDiscovery(context: context)
        .discover(scheme: "NoScheme")
    #expect(destinations.isEmpty)
}
```

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

### Running on Linux (Docker)

`GradleKit`, `ShipItKit` core, and `CLI` tests run on Linux. macOS-only targets (`XcodeBuildKitTests`, `XcodeGenKitTests`, `IntegrationTests`) are skipped automatically. Use the `Makefile` targets to run the Linux-compatible subset via Docker — no local Swift toolchain needed:

```bash
# Direct volume mount — fastest for iterative runs
make test-linux                  # run tests
make test-linux-coverage         # run tests with --enable-code-coverage
make shell-linux                 # interactive shell for debugging

# Image-based (caches SPM deps as a Docker layer)
make docker-build && make docker-test
```

---

## Infrastructure Retry Testing

The `InfrastructureRetryScheduler` and platform-specific classifiers have dedicated tests:

```bash
swift test --filter "TestActionTests/retriesInfrastructureFailureAndRecovers"
swift test --filter "TestActionTests/doesNotRetryNormalTestFailures"
swift test --filter "TestActionTests/infrastructureFailureClassifierMatchesRunnerLaunch"
swift test --filter "TestActionTests/androidClassifierMatchesEmulatorDisconnect"
swift test --filter "TestActionTests/flutterClassifierMatchesToolCrash"
swift test --filter "TestActionTests/reactNativeClassifierMatchesWorkerFailure"
swift test --filter "TestActionTests/schedulerBackoffAndJitter"
```

### Testing with infrastructure retry enabled

```swift
@Test("Retries iOS infrastructure failures and succeeds on a later attempt")
func retriesInfrastructureFailureAndRecovers() async throws {
    let attempts = Mutex(0)
    let (executor, commands) = makeCaptureExecutor { _, _ in
        let attempt = attempts.withLock { $0 += 1; return $0 }
        if attempt == 1 {
            throw ShellError.exitFailure(
                command: "xcodebuild test",
                output: ShellOutput(
                    stdout: "",
                    stderr: "Simulator device failed to launch com.example.xctrunner. The process failed to launch.",
                    exitCode: 65
                )
            )
        }
        return ShellOutput(stdout: "Executed 2 tests, with 0 failures\n", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)

    let result = try await TestAction().run(
        with: .init(
            scheme: "MockApp",
            destination: "platform=iOS Simulator,name=iPhone 16",
            infrastructureRetry: .init(maxAttempts: 2, initialDelaySeconds: 0)
        ),
        context: context
    )

    #expect(result.passCount == 2)
    #expect(commands().count == 2) // one failure + one success
}
```

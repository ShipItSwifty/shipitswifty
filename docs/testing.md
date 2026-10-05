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

### Real cross-platform e2e fixtures

Two full apps are vendored in-repo and exercised with the **real** toolchains:

- `Tests/IntegrationTests/Fixtures/flutter-app/` — a complete Flutter app.
- `Tests/IntegrationTests/Fixtures/react-native-app/` — a complete React Native app, pinned to a stable RN release (`react-native@0.85.3`).

Both are committed **source-only**. Dependencies are regenerated into a per-test temp copy at bootstrap:
`flutter pub get` for Flutter, `npm install` for RN, and `pod install` for RN iOS (CocoaPods are **not** committed). The Gradle wrapper jars and `package-lock.json` / `pubspec.lock` **are** committed for reproducibility.

The suites (`FlutterE2ETests`, `ReactNativeE2ETests`) are tiered, gated by tags and env flags so a plain run stays fast:

| Tier | Tag | Gate | What runs |
|---|---|---|---|
| Quick | `.e2eQuick` | `SHIPIT_E2E=1` (+ `flutter` / Node on PATH) | `shipit test` + `shipit lint` |
| Build | `.e2eBuild` | `SHIPIT_E2E_BUILD=1` | `shipit build` (logs elapsed time) |
| Full | `.e2eFull` | `SHIPIT_E2E_FULL=1` | `archive`, code signing, `validate bundle/archive` |

Every tier is opt-in. Even the quick tier regenerates dependencies (`flutter pub get` / `npm install`) into a temp copy before invoking `shipit`, so a plain `swift test` does **not** run it — it skips cleanly unless `SHIPIT_E2E=1` is set. The build/full gates imply the quick tier too.

```bash
swift build

# Quick tier (opt-in; also needs flutter / node on PATH):
SHIPIT_E2E=1 swift test --filter FlutterE2ETests
SHIPIT_E2E=1 swift test --filter ReactNativeE2ETests

# Build tier — confirm the fixtures compile; watch the "⏱ [e2e] …" timing lines:
SHIPIT_E2E_BUILD=1 swift test --filter FlutterE2ETests
SHIPIT_E2E_BUILD=1 swift test --filter ReactNativeE2ETests

# Full tier — archive + code signing (iOS signing also needs SHIPIT_TEST_TEAM_ID + a signing identity):
SHIPIT_E2E_FULL=1 swift test --filter E2ETests
```

iOS build/archive tiers additionally require Xcode (and CocoaPods for RN); Android tiers require the Android SDK. Each missing prerequisite skips its tests cleanly rather than failing.

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

## Test lanes and portable evidence

This repository defines its checks in `Shipfile.yml`. After `swift build`, run
`"$(swift build --show-bin-path)/shipit" test --workflow ci-macos` (or `ci-linux`).
The `format`, `fixtures`, and `integration-advisory` workflows preserve the previous
formatting scopes, platform exclusions, fixture suites, and advisory integration policy.
CI keeps the initial unit coverage snapshot separate from later integration runs for Codecov.

For a library with an Xcode sample, compose ordinary actions in one named lane:

```yaml
test_workflow: tests
app:
  project: Examples/Sample/Sample.xcodeproj
  scheme: Sample
workflows:
  tests:
    - action: swift-format
      options: { paths: [Sources, Tests] }
    - action: swift-test
      options:
        enable_code_coverage: true
        output_directory: "build/tests/{{run_id}}/package"
        environment: { SNAPSHOT_RECORD_MODE: never }
        rerun_failed_tests: { enabled: true, max_attempts: 2 }
        infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }
    - action: coverage
      options:
        input_format: swift
        report_path: "build/tests/{{run_id}}/package/coverage.json"
        source_roots: [Sources/MyLibrary]
        exclude_previews: true
        minimum_coverage: 80
    - action: test
      options:
        test_plans: [Sample, SampleLocales]
        destinations: ["platform=iOS Simulator,name=iPhone 17,OS=27.2"]
        skip_macro_validation: true
        rerun_failed_tests: { enabled: true, max_attempts: 2 }
        infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }
      artifacts:
        - name: test-evidence
          paths: ["build/tests/{{run_id}}", "build/workflow-artifacts/{{run_id}}/test-runs"]
          retention_days: 14
```

`shipit test` selects `test_workflow`; `shipit test --workflow tests` selects it explicitly.
Workflows stop on failure by default. Use object syntax with `continue_on_failure: true`
and `steps:` only when checks are independent; the overall exit status still fails.

Native Xcode lanes build `.xctestproducts` once, then run each plan and destination with
`test-without-building`. Simulator/device mixtures and locally discoverable plans with
incompatible target sets require separate steps. Xcode controls parallel workers. A
classified clone failure switches that destination to serial once and reuses the products;
assertion failures do not trigger this fallback. `serial: true` forces serial execution.
`legacy_combined_test: true` preserves the previous `xcodebuild test` invocation.

Each attempt retains commands, stdout/stderr, results and native evidence before another
attempt can overwrite it. SwiftPM reruns use `--skip-build`; SwiftPM, Flutter, Android JVM,
and Xcode reruns use normalized selectors. `max_attempts` includes the initial assertion
run. Infrastructure retry budgets are separate; recovered assertions pass and remain marked
flaky. Instrumented Android and Kotlin Native tests retain results but do not claim selective
assertion-rerun support. Saved Swift Testing streams require a Swift toolchain supporting
`--event-stream-output-path` and `--attachments-path`.

Simulator claims use amoo's `AMOO_LEASE_DIR` / `~/.amoo/leases` protocol. ShipIt refuses held
devices and releases its own leases on completion/error/cancellation. It shuts down only
simulators it booted and refuses to erase an already booted simulator. Shutdown is best effort
when cancellation interrupts the shell; its own lease is still released. Known Xcode processes
holding an explicit UDID are reported with their PID and command. Runners that neither use a
lease nor expose their destination in their command cannot be detected reliably. Failure
screenshots and bounded device logs are best effort; unavailable device state is recorded as
`unknown`, and native attachment associations are retained.

Inspect saved results without running tests or requiring a Shipfile:

```bash
shipit test-results --input results.xcresult --export-directory artifacts/ios
shipit test-results --input app/build/test-results/testDebugUnitTest --runner gradle
shipit test-results --input shared/build/test-results/iosSimulatorArm64Test --runner kmp
shipit test-results --input flutter-events.jsonl --input-format flutter
shipit test-results --input swift-events.jsonl --input-format swift
shipit test-results --input artifacts/ios/manifest.json --format markdown
shipit coverage --input-format kover --report build/reports/kover/report.xml
shipit coverage --input-format lcov --report coverage/lcov.info
```

Repeated `--input`, `--coverage-input` (with `--coverage-format`), and `--evidence` allow results,
coverage, screenshots, videos and logs to be exported together. Export creates a **new** directory
with normalized results, coverage, originals, extracted xcresult attachments/diagnostics/logs,
a manifest and an index with relative links (including a per-report coverage summary; reports are
never summed). The export is assembled in a hidden sibling directory and renamed into place only when
complete, so a failed or cancelled export leaves nothing behind and the same path can be retried
(a hard-killed process can leave a `.<name>.partial-*` directory, which is safe to delete). Symbolic
links in sources are followed so the export holds real files. `results.json` and `coverage.json` carry a
`schemaVersion`, and `results.json` can be passed straight to `--input`. It never overwrites a prior export. Malformed
inputs fail; optional missing evidence produces diagnostics. Filtering the displayed cases
never changes the full-run summary. xcresult extraction requires macOS/Xcode; portable exported
results, JUnit, Swift events, Flutter events, Jest, LCOV and JVM coverage can be read on Linux.

A run that reports no test outcomes is never a passing zero-test run: offline inspection rejects
empty or unreadable artifacts, and live Flutter/KMP runs that exit 0 without results fail with an
error report (Gradle's `NO-SOURCE` is the one legitimate empty run). Gradle result directories are
cleared before each run so a build that fails before executing tests cannot reuse the previous
run's XML. Test IDs for Gradle JUnit XML are relative to the Gradle project (the nearest directory with
`settings.gradle[.kts]` or `gradlew`), so live and offline inspection agree and the same test in two
modules stays distinct; JUnit stack traces and output written as CDATA are preserved.

`report.json` always describes the whole run. The recorder keeps one directory per attempt and does
not rewrite the report per attempt; if an action stops before writing its final report (cancellation, an
I/O error, a failing run), a provisional report is written from the reconciled attempts: the first full
run's identities, failures still unresolved by reruns, and flaky recoveries. A run that stopped for any
reason other than failing tests carries one extra `errored` so it can never read as a clean pass. Android
follows the same zero-result policy as Flutter and KMP: exiting 0 without JUnit XML fails unless Gradle
reported `NO-SOURCE` or `SKIPPED` for that exact test task. Saving evidence is best effort: a failure to
write logs, snapshots or reports is logged and never replaces or hides the test outcome; an unreadable
SwiftPM rerun keeps the original failures as persistent.

JUnit XML keeps a failure's `message` and `stackTrace` apart (a body-only failure uses its first line
as the message), plus the `failure_type`. Every test reports `attempts`, how many times the runner
executed it, so a test that passes after retrying is visible rather than looking like an ordinary pass.
Retry plugins (Gradle `test-retry`) write one `testcase` per attempt; when a repeated name includes a
failure, the attempts are folded into one test: the last attempt decides the status, `attempts` counts
them all, `durationSeconds` is the deciding attempt and `totalDurationSeconds` is what every attempt
cost, `first_failure` keeps why it first failed, and a test that passed after a failure is marked
`flaky` (and counted in `summary.flaky`). Surefire `flakyFailure` / `rerunFailure` elements are
counted the same way, and a retry's own message and output never replace the final result. A name that
repeats with every occurrence passing is a genuine duplicate, not a retry: each keeps its own ID (the
first the plain ID, later ones `#<n>`, with an `occurrence` of `n/total`). Each case records its
`report` location and, from the Gradle layout and the properties AGP writes for connected runs, its
`module`, `task`, `device`, `flavor` and `project`, so the same test on two devices stays distinct. When
the suites' declared totals (restated for folded attempts) disagree with the listed test cases a
warning diagnostic says so.

Coverage gates use executable lines, reject empty input and merge overlapping source lines.
SwiftPM uses LLVM JSON, Flutter uses LCOV, and Android/KMP JVM use JaCoCo-compatible XML
(including Kover). Coverage for Kotlin Native/JS is unavailable through these formats.
Original artifacts preserve additional runner metrics beyond the normalized line summary.

Test steps expose `{{test_output_directory}}`, `{{test_report_path}}`, and
`{{test_result_bundle}}` when produced. SwiftPM steps also expose `{{coverage_path}}`.
Use these paths in later steps or artifact declarations instead of guessing output names.

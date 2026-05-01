import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestAction")
struct TestActionTests {

    // MARK: - Success parsing

    @Test("Parses executed test count and forwards explicit result bundle path")
    func parsesSuccessfulOutput() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "Executed 5 tests, with 0 failures (0 unexpected) in 1.234 (1.567) seconds\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                resultBundlePath: "/tmp/Test.xcresult"
            ),
            context: context
        )

        #expect(result.passCount == 5)
        #expect(result.failCount == 0)
        #expect(result.skipCount == 0)
        #expect(result.resultBundlePath == "/tmp/Test.xcresult")
        #expect(result.succeeded)
    }

    @Test("Parses skipped test count from summary line")
    func parsesSkipCount() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                // "2 skipped" precedes "0 failures"
                stdout: "Executed 10 tests, with 2 skipped and 0 failures (0 unexpected) in 2.000 (2.100) seconds\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 16"),
            context: context
        )

        #expect(result.passCount == 8)
        #expect(result.skipCount == 2)
        #expect(result.failCount == 0)
    }

    // MARK: - Multi-destination

    @Test("Aggregates pass/skip counts across multiple destinations")
    func aggregatesCountsAcrossDestinations() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "Executed 5 tests, with 0 failures (0 unexpected) in 1.000 (1.100) seconds\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destinations: [
                    "platform=iOS Simulator,name=iPhone 16",
                    "platform=iOS Simulator,name=iPhone 15",
                ]
            ),
            context: context
        )

        // 5 pass × 2 destinations = 10 total
        #expect(result.passCount == 10)
        #expect(result.failCount == 0)
        #expect(result.skipCount == 0)
    }

    @Test("destinations array takes precedence over legacy destination string")
    func destinationsArrayWinsOverLegacyDestination() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destinations: ["platform=iOS Simulator,name=iPhone 16 Pro"],
                destination: "platform=iOS Simulator,name=iPhone 14"  // should be ignored
            ),
            context: context
        )

        #expect(commands().count == 1, "Only one destination should be used")
        #expect(commands()[0].contains("iPhone 16 Pro"))
        #expect(!commands()[0].contains("iPhone 14"))
    }

    @Test("Legacy single destination string is promoted to one-element destinations list")
    func legacyDestinationIsPromoted() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 15"),
            context: context
        )

        #expect(commands().count == 1)
        #expect(commands()[0].contains("iPhone 15"))
    }

    // MARK: - Missing destinations guard

    @Test("Throws invalidConfiguration when no destinations are provided")
    func throwsWhenNoDestinations() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(with: .init(scheme: "MockApp"), context: context)
            Issue.record("Expected TestAction to throw when no destinations are configured")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected .invalidConfiguration, got \(error)")
                return
            }
        }
    }

    @Test("Throws invalidConfiguration when destinations is an empty array")
    func throwsWhenDestinationsArrayIsEmpty() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(
                with: .init(scheme: "MockApp", destinations: []),
                context: context
            )
            Issue.record("Expected TestAction to throw when destinations is empty")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected .invalidConfiguration, got \(error)")
                return
            }
        }
    }

    // MARK: - Failure parsing

    @Test("Parses failure count from bulk summary line")
    func parsesFailureCountFromSummary() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "** TEST FAILED ** (3 failures)\n",
                stderr: "",
                exitCode: 65
            )
        }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(
                with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 16"),
                context: context
            )
            Issue.record("Expected TestAction to throw")
        } catch let error as ShipItError {
            guard case .testFailed(let exitCode, let failureCount, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(exitCode == 65)
            #expect(failureCount == 3)
        }
    }

    @Test("Parses failure count from singular form '(1 failure)'")
    func parsesFailureCountSingular() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "** TEST FAILED ** (1 failure)\n",
                stderr: "",
                exitCode: 65
            )
        }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(
                with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 16"),
                context: context
            )
            Issue.record("Expected TestAction to throw")
        } catch let error as ShipItError {
            guard case .testFailed(_, let failureCount, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(failureCount == 1)
        }
    }

    @Test("Counts per-test FAILED lines as fallback (parallel output)")
    func parsesPerTestFailureLines() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: """
                    MyTests.testFoo: FAILED
                    MyTests.testBar: FAILED
                    """,
                stderr: "",
                exitCode: 65
            )
        }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(
                with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 16"),
                context: context
            )
            Issue.record("Expected TestAction to throw")
        } catch let error as ShipItError {
            guard case .testFailed(_, let failureCount, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(failureCount == 2)
        }
    }

    // MARK: - Coverage

    @Test("Auto-derives result bundle path when enableCodeCoverage is true and no explicit path given")
    func autoDerivesResultBundlePathForCoverage() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                enableCodeCoverage: true
            ),
            context: context
        )

        #expect(result.resultBundlePath == "./build/MockApp-tests.xcresult")
        let command = commands().first ?? ""
        #expect(command.contains("-enableCodeCoverage YES"))
        #expect(command.contains("-resultBundlePath ./build/MockApp-tests.xcresult"))
    }

    @Test("Explicit resultBundlePath takes precedence over auto-derived path when coverage enabled")
    func explicitPathTakesPrecedenceOverAutoPath() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                enableCodeCoverage: true,
                resultBundlePath: "/custom/path.xcresult"
            ),
            context: context
        )

        #expect(result.resultBundlePath == "/custom/path.xcresult")
        let command = commands().first ?? ""
        #expect(command.contains("-resultBundlePath /custom/path.xcresult"))
        #expect(!command.contains("MockApp-tests.xcresult"))
    }

    // MARK: - Stale result bundle cleanup

    @Test("Removes stale result bundle before running tests when explicit path is set")
    func removesStaleResultBundleBeforeRun() async throws {
        // Create a temporary directory to act as a stale .xcresult bundle
        let fm = FileManager.default
        let tmpDir = NSTemporaryDirectory()
        let bundlePath = (tmpDir as NSString).appendingPathComponent("StaleBundle-\(Int(Date().timeIntervalSince1970)).xcresult")
        try fm.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        #expect(fm.fileExists(atPath: bundlePath), "Pre-condition: stale bundle must exist before action runs")

        defer { try? fm.removeItem(atPath: bundlePath) }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "Executed 3 tests, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                resultBundlePath: bundlePath
            ),
            context: context
        )

        #expect(result.passCount == 3)
        #expect(result.resultBundlePath == bundlePath)
        // The stale bundle was removed; xcodebuild (mocked) did not recreate it
        #expect(!fm.fileExists(atPath: bundlePath), "Stale bundle should have been removed before xcodebuild ran")
    }

    @Test("Removes auto-derived stale result bundle before running tests when coverage is enabled")
    func removesAutoDeriveStaleBundleForCoverage() async throws {
        let fm = FileManager.default
        // Use a distinct scheme name to avoid path collision with other tests.
        // Auto-derived path pattern: ./build/<scheme>-tests.xcresult
        let scheme = "StaleCoverageApp"
        let cwd = fm.currentDirectoryPath
        let buildDir = (cwd as NSString).appendingPathComponent("build")
        let bundlePath = (buildDir as NSString).appendingPathComponent("\(scheme)-tests.xcresult")

        // Create build dir + stale bundle if needed
        try? fm.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: bundlePath) {
            try fm.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        }
        #expect(fm.fileExists(atPath: bundlePath), "Pre-condition: stale auto-derived bundle must exist")

        defer { try? fm.removeItem(atPath: bundlePath) }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "Executed 2 tests, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: scheme,
                destination: "platform=iOS Simulator,name=iPhone 16",
                enableCodeCoverage: true
            ),
            context: context
        )

        // The auto-derived stale bundle was removed before xcodebuild ran
        #expect(!fm.fileExists(atPath: bundlePath), "Auto-derived stale bundle should have been removed before xcodebuild ran")
    }

    // MARK: - xcodebuild flag passthrough

    @Test("Emits -enableCodeCoverage, -resultBundlePath, and -testPlan flags")
    func emitsCoverageAndTestPlanFlags() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                enableCodeCoverage: true,
                resultBundlePath: "/tmp/Tests.xcresult",
                testPlan: "Smoke"
            ),
            context: context
        )

        let command = commands().first ?? ""
        #expect(command.contains("-enableCodeCoverage YES"))
        #expect(command.contains("-resultBundlePath /tmp/Tests.xcresult"))
        #expect(command.contains("-testPlan Smoke"))
    }

    @Test("Emits -only-testing for each target in onlyTesting array")
    func emitsOnlyTestingFlags() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 2 tests, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                onlyTesting: ["MockAppTests/FeatureATests", "MockAppTests/FeatureBTests"]
            ),
            context: context
        )

        let command = commands().first ?? ""
        #expect(command.contains("-only-testing MockAppTests/FeatureATests"))
        #expect(command.contains("-only-testing MockAppTests/FeatureBTests"))
    }

    @Test("Emits -skip-testing for each target in skipTesting array")
    func emitsSkipTestingFlags() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 4 tests, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                skipTesting: ["MockAppTests/SlowTests"]
            ),
            context: context
        )

        let command = commands().first ?? ""
        #expect(command.contains("-skip-testing MockAppTests/SlowTests"))
    }

    @Test("Emits -retry-tests-on-failure when retryOnFailure is true")
    func emitsRetryFlag() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destination: "platform=iOS Simulator,name=iPhone 16",
                retryOnFailure: true
            ),
            context: context
        )

        let command = commands().first ?? ""
        #expect(command.contains("-retry-tests-on-failure"))
    }

    @Test("Does not emit -retry-tests-on-failure when retryOnFailure is nil or false")
    func omitsRetryFlagByDefault() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(scheme: "MockApp", destination: "platform=iOS Simulator,name=iPhone 16"),
            context: context
        )

        let command = commands().first ?? ""
        #expect(!command.contains("-retry-tests-on-failure"))
    }

    // MARK: - Auto-discovery of simulator destinations

    @Test("Auto-discovers iPhone simulator when no destinations configured")
    func autoDiscoversiPhoneSimulator() async throws {
        nonisolated(unsafe) var callIndex = 0
        let executor = MockExecutor { command, _ in
            let desc = command.description
            callIndex += 1
            // First call: xcodebuild -showdestinations (from DestinationDiscovery)
            if desc.contains("-showdestinations") || desc.contains("showDestinations") {
                return ShellOutput(
                    stdout: """
                        Available destinations for the "MockApp" scheme:
                            { platform:iOS Simulator, id:SIM-1, OS:18.2, name:iPhone 16 Pro }
                            { platform:iOS Simulator, id:SIM-2, OS:18.2, name:iPhone 16 }
                            { platform:iOS Simulator, id:SIM-3, OS:17.5, name:iPhone 15 }
                        """,
                    stderr: "",
                    exitCode: 0
                )
            }
            // Second call: xcodebuild test (the actual test run)
            return ShellOutput(
                stdout: "Executed 5 tests, with 0 failures (0 unexpected) in 1.234 (1.567) seconds\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        // No destinations or destination in options — should auto-discover
        let result = try await TestAction().run(
            with: .init(scheme: "MockApp"),
            context: context
        )

        #expect(result.passCount == 5)
        #expect(result.failCount == 0)
    }

    @Test("Auto-discovery prefers highest OS version and Pro models")
    func autoDiscoveryPrefersBestSimulator() async throws {
        let (executor, commands) = makeCaptureExecutor { command, _ in
            let desc = command.description
            if desc.contains("-showdestinations") || desc.contains("showDestinations") {
                return ShellOutput(
                    stdout: """
                            { platform:iOS Simulator, id:SIM-1, OS:17.5, name:iPhone 15 Pro }
                            { platform:iOS Simulator, id:SIM-2, OS:18.2, name:iPhone 16 }
                            { platform:iOS Simulator, id:SIM-3, OS:18.2, name:iPhone 16 Pro }
                        """,
                    stderr: "",
                    exitCode: 0
                )
            }
            return ShellOutput(
                stdout: "Executed 1 test, with 0 failures\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(with: .init(scheme: "MockApp"), context: context)

        // The test run command (second call) should use the iPhone 16 Pro (highest OS + Pro)
        let testCommand = commands().last ?? ""
        #expect(testCommand.contains("iPhone 16 Pro"))
    }

    @Test("Auto-discovery throws when only non-iPhone simulators are available")
    func autoDiscoveryThrowsWhenNoiPhones() async throws {
        let executor = MockExecutor { command, _ in
            let desc = command.description
            if desc.contains("-showdestinations") || desc.contains("showDestinations") {
                return ShellOutput(
                    stdout: """
                            { platform:iOS Simulator, id:SIM-1, OS:18.2, name:Apple Watch Series 9 }
                            { platform:macOS, id:MAC-1, name:My Mac }
                        """,
                    stderr: "",
                    exitCode: 0
                )
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(with: .init(scheme: "MockApp"), context: context)
            Issue.record("Expected TestAction to throw when no iPhone simulators found")
        } catch let error as ShipItError {
            guard case .invalidConfiguration(let reason) = error else {
                Issue.record("Expected .invalidConfiguration, got \(error)")
                return
            }
            #expect(reason.contains("Could not auto-discover"))
        }
    }

    @Test("Auto-discovery skips when explicit destinations are provided")
    func autoDiscoverySkippedWithExplicitDestinations() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "Executed 1 test, with 0 failures\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                destinations: ["platform=iOS Simulator,name=iPhone 15,OS=17.5"]
            ),
            context: context
        )

        // Should NOT have called -showdestinations since explicit destinations were given
        #expect(!commands().contains { $0.contains("-showdestinations") || $0.contains("showDestinations") })
        // Should have used the explicit destination
        #expect(commands().contains { $0.contains("iPhone 15") })
    }

    // MARK: - Missing scheme

    @Test("Throws invalidConfiguration when no scheme is resolvable")
    func throwsWhenNoScheme() async throws {
        // Build a context whose config has no appScheme so the guard in TestAction fires.
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor)
        let config = ResolvedConfig(appScheme: nil, bundleID: "com.example.mock", teamID: "T123")
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: shell,
            logger: .forType(subsystem: "ShipItSwiftyTests", TestAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        do {
            _ = try await TestAction().run(with: .init(), context: context)
            Issue.record("Expected TestAction to throw")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected .invalidConfiguration, got \(error)")
                return
            }
        }
    }
}

import Foundation
import SwiftyShell
import Testing

@testable import ShipItCLI
@testable import ShipItKit

// MARK: - CLI Build Integration Tests

@Suite("CLI Build")
struct CLIBuildTests {

    @Test("Action descriptors decode snake_case workflow options")
    func actionDescriptorDecodesSnakeCaseOptions() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let descriptor = SnakeCaseAction.descriptor(for: SnakeCaseAction())

        let result = try await descriptor.runJSON(
            .object([
                "ipa_path": .string("./build/MyApp.ipa"),
                "submit_for_review": .bool(true),
                "phased_release": .bool(true),
            ]),
            context
        )

        #expect(result.action == "snake-case")
        #expect(result.status == "success")
        #expect(result.payload?.objectValue?["ipaPath"] == .string("./build/MyApp.ipa"))
        #expect(result.payload?.objectValue?["submitForReview"] == .bool(true))
        #expect(result.payload?.objectValue?["phasedRelease"] == .bool(true))
    }

    #if os(macOS)
    @Test("Metadata command parses review submission flags")
    func metadataCommandParsesReviewFlags() throws {
        let command =
            try MetadataCommand.parseAsRoot([
                "--push",
                "--submit-for-review",
                "--automatic-release",
                "--phased-release",
            ]) as! MetadataCommand

        #expect(command.push)
        #expect(command.submitForReview)
        #expect(command.automaticRelease)
        #expect(command.phasedRelease)
    }
    #endif

    @Test("Env command preserves explicit shipfile path")
    func envCommandParsesShipfileOption() throws {
        let command =
            try EnvCommand.parseAsRoot([
                "--shipfile",
                "/tmp/MissingShipfile.yml",
            ]) as! EnvCommand

        #expect(command.global.shipfile == "/tmp/MissingShipfile.yml")
    }

    @Test("Global options parse explicit color mode")
    func globalOptionsParseColorMode() throws {
        let command =
            try BuildCommand.parseAsRoot([
                "--color",
                "always",
            ]) as! BuildCommand

        #expect(command.global.color == .always)
        #expect(command.global.effectiveColorMode == .always)
    }

    @Test("Global options let no-color override color mode")
    func globalOptionsParseNoColorOverride() throws {
        let command =
            try BuildCommand.parseAsRoot([
                "--color",
                "always",
                "--no-color",
            ]) as! BuildCommand

        #expect(command.global.color == .always)
        #expect(command.global.noColor)
        #expect(command.global.effectiveColorMode == .never)
    }

    @Test("Build command parses Gradle module and variant")
    func buildCommandParsesGradleOptions() throws {
        let command =
            try BuildCommand.parseAsRoot([
                "--platform", "android",
                "--module", "androidApp",
                "--build-variant", "debug",
            ]) as! BuildCommand

        #expect(command.global.platform == .android)
        #expect(command.module == "androidApp")
        #expect(command.buildVariant == "debug")
    }

    @Test("Archive command parses Gradle module and variant")
    func archiveCommandParsesGradleOptions() throws {
        let command =
            try ArchiveCommand.parseAsRoot([
                "--platform", "android",
                "--module", "androidApp",
                "--build-variant", "release",
            ]) as! ArchiveCommand

        #expect(command.global.platform == .android)
        #expect(command.module == "androidApp")
        #expect(command.buildVariant == "release")
    }

    @Test("Test command parses Gradle module variant and device options")
    func testCommandParsesGradleOptions() throws {
        let command =
            try TestCommand.parseAsRoot([
                "--platform", "android",
                "--kind", "instrumented",
                "--scope", "root",
                "--module", "androidApp",
                "--build-variant", "debug",
                "--device-strategy", "named_emulators",
                "--emulators", "Pixel_9_API_35",
                "--emulators", "Pixel_Tablet_API_35",
                "--prompt-locally",
            ]) as! TestCommand

        #expect(command.global.platform == .android)
        #expect(command.kind == .instrumented)
        #expect(command.scope == .root)
        #expect(command.module == "androidApp")
        #expect(command.buildVariant == "debug")
        #expect(command.deviceStrategy == .namedEmulators)
        #expect(command.emulators == ["Pixel_9_API_35", "Pixel_Tablet_API_35"])
        #expect(command.promptLocally)
    }

    @Test("Test command parses rerun and report options")
    func testCommandParsesRerunOptions() throws {
        let command =
            try TestCommand.parseAsRoot([
                "--rerun-failed-tests",
                "--max-rerun-attempts", "2",
                "--report-path", "./artifacts/test-report.json",
            ]) as! TestCommand

        #expect(command.rerunFailedTests)
        #expect(command.maxRerunAttempts == 2)
        #expect(command.reportPath == "./artifacts/test-report.json")
    }

    #if os(macOS)
    @Test("BuildAction returns Result with exitCode 0 on success")
    func buildSuccessResult() async throws {
        let executor = MockExecutor { command, _ in
            ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = BuildAction.Options(scheme: "MockApp", configuration: .release)

        let result = try await BuildAction().run(with: options, context: context)
        #expect(result.exitCode == 0)
    }

    @Test("BuildAction wraps failure as ShipItError.buildFailed")
    func buildFailureWrapping() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "xcodebuild: error: 'MockApp' scheme not found\n", exitCode: 65)
        }
        let context = ActionContext.mock(executor: executor)
        let options = BuildAction.Options(scheme: "MockApp", configuration: .release)

        do {
            _ = try await BuildAction().run(with: options, context: context)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ShipItError {
            guard case .buildFailed(let code, _) = error else {
                #expect(Bool(false), "Expected .buildFailed, got: \(error)")
                return
            }
            #expect(code == 65)
        }
    }
    #endif

    @Test("ActionResultEnvelope encodes to correct JSON shape")
    func resultEnvelopeEncoding() throws {
        let envelope = ActionResultEnvelope(
            action: "build",
            status: "success",
            payload: .object(["exitCode": .int(0)])
        )

        let reporter = JSONReporter(prettyPrint: false)
        let json = try reporter.encode(envelope)

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ActionResultEnvelope.self, from: data)

        #expect(decoded.action == "build")
        #expect(decoded.status == "success")
        #expect(decoded.payload?.objectValue?["exitCode"] == .int(0))
    }

    @Test("Workflow version summary includes build number")
    func workflowVersionSummaryIncludesBuildNumber() {
        let summary = humanStepSummary(
            action: "version",
            payload: .object([
                "version": .string("0.1.0"),
                "buildNumber": .string("42"),
            ])
        )

        #expect(summary == "0.1.0 (42)")
    }

    @Test("Workflow test summary labels passed count as tests")
    func workflowTestSummaryLabelsPassedCountAsTests() {
        let summary = humanStepSummary(
            action: "test",
            payload: .object([
                "passCount": .int(3),
                "failCount": .int(0),
                "skipCount": .int(0),
            ])
        )

        #expect(summary == "3 tests passed")
    }

    @Test("Workflow test summary labels fail and skip counts as tests")
    func workflowTestSummaryLabelsFailAndSkipCountsAsTests() {
        let summary = humanStepSummary(
            action: "test",
            payload: .object([
                "passCount": .int(3),
                "failCount": .int(1),
                "skipCount": .int(2),
            ])
        )

        #expect(summary == "3 tests passed, 1 test failed, 2 tests skipped")
    }

    @Test("Workflow test summary prefers named passed and failed tests")
    func workflowTestSummaryPrefersNamedTests() {
        let summary = humanStepSummary(
            action: "test",
            payload: .object([
                "passCount": .int(2),
                "failCount": .int(1),
                "skipCount": .int(1),
                "passedTests": .array([
                    .string("FeatureTests.testHappyPath"),
                    .string("FeatureTests.testRetry"),
                ]),
                "failedTests": .array([
                    .string("FeatureTests.testOfflineMode"),
                ]),
            ])
        )

        #expect(summary == "passed: FeatureTests.testHappyPath, FeatureTests.testRetry, failed: FeatureTests.testOfflineMode, 1 test skipped")
    }

    @Test("Workflow test summary truncates long named test lists")
    func workflowTestSummaryTruncatesLongNamedTestLists() {
        let summary = humanStepSummary(
            action: "test",
            payload: .object([
                "passCount": .int(5),
                "failCount": .int(0),
                "skipCount": .int(0),
                "passedTests": .array([
                    .string("FeatureTests.testOne"),
                    .string("FeatureTests.testTwo"),
                    .string("FeatureTests.testThree"),
                    .string("FeatureTests.testFour"),
                    .string("FeatureTests.testFive"),
                ]),
            ])
        )

        #expect(summary == "passed: FeatureTests.testOne, FeatureTests.testTwo, FeatureTests.testThree, +2 more")
    }

    @Test("ActionContext.mock creates valid context")
    func mockContextCreation() {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        #expect(context.config.appScheme == "MockApp")
        #expect(context.platform == .ios)
    }

    @Test("Workflow executes steps in order")
    func workflowStepOrder() async throws {
        nonisolated(unsafe) var executedActions: [String] = []

        let executor = MockExecutor { command, _ in
            let desc = command.description
            if desc.contains("xcodebuild") {
                // Simulate successful build/archive
                return ShellOutput(stdout: "Succeeded\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let registry = ActionRegistry()

        // Register a mock "track" action
        let trackDescriptor = ActionDescriptor(name: "track", description: "Track") { _, _ in
            executedActions.append("track")
            return ActionResultEnvelope(action: "track", status: "success", payload: nil)
        }
        try await registry.register(trackDescriptor)

        let workflow = Workflow("test-workflow") {
            WorkflowStep(action: "track")
            WorkflowStep(action: "track")
        }

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.stepResults.count == 2)
        #expect(result.stepResults[0].action == "track")
        #expect(result.stepResults[1].action == "track")
        #expect(executedActions == ["track", "track"])
    }

    @Test("Workflow throws on unknown action")
    func workflowUnknownAction() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let registry = ActionRegistry()

        let workflow = Workflow("test", steps: [WorkflowStep(action: "nonexistent-action")])

        await #expect {
            _ = try await workflow.run(context: context, registry: registry)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("nonexistent-action")
        }
    }

    @Test("Workflow generic success rows do not use trailing checkmark summary")
    func workflowGenericSuccessRowsDoNotUseTrailingCheckmarkSummary() {
        let summary = humanStepSummary(action: "lint", payload: nil)
        #expect(summary == nil)
    }
}

private struct SnakeCaseAction: Action {
    struct Options: Codable, Sendable {
        let ipaPath: String?
        let submitForReview: Bool?
        let phasedRelease: Bool?
    }

    struct Result: Codable, Sendable {
        let ipaPath: String?
        let submitForReview: Bool?
        let phasedRelease: Bool?
    }

    static let name = "snake-case"
    static let description = "Verifies snake_case option decoding"

    func run(with options: Options, context: ActionContext) async throws -> Result {
        Result(
            ipaPath: options.ipaPath,
            submitForReview: options.submitForReview,
            phasedRelease: options.phasedRelease
        )
    }
}

// MARK: - RetryPolicy Tests

@Suite("RetryPolicy")
struct RetryPolicyTests {

    @Test("RetryPolicy succeeds on first attempt")
    func successFirstAttempt() async throws {
        nonisolated(unsafe) var callCount = 0
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .seconds(0))

        let result = try await policy.execute {
            callCount += 1
            return "success"
        }

        #expect(result == "success")
        #expect(callCount == 1)
    }

    @Test("RetryPolicy retries on failure and eventually succeeds")
    func retryUntilSuccess() async throws {
        nonisolated(unsafe) var callCount = 0
        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(10))

        let result = try await policy.execute { () -> String in
            callCount += 1
            if callCount < 3 {
                throw ShipItError.invalidConfiguration(reason: "Simulated failure")
            }
            return "success"
        }

        #expect(result == "success")
        #expect(callCount == 3)
    }

    @Test("RetryPolicy throws after maxAttempts exhausted")
    func exhaustRetries() async throws {
        nonisolated(unsafe) var callCount = 0
        let policy = RetryPolicy(maxAttempts: 2, initialDelay: .milliseconds(10))

        await #expect {
            _ = try await policy.execute { () -> String in
                callCount += 1
                throw ShipItError.invalidConfiguration(reason: "Always fails")
            }
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason == "Always fails"
        }
        #expect(callCount == 2)
    }
}

import OSLog
import SwiftyShell

/// Runs unit and UI tests using `xcodebuild test`.
///
/// Outputs JUnit XML and code coverage data. The action fails if any test
/// reports a failure (non-zero exit code).
///
/// ## Usage
/// ```swift
/// let result = try await TestAction().run(
///     with: .init(scheme: "MyApp", destination: "iPhone 16"),
///     context: context
/// )
/// print("Passed: \(result.passCount), Failed: \(result.failCount)")
/// ```
public struct TestAction: Action {
    public static let name = "test"
    public static let description = "Run unit and UI tests using xcodebuild test"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestAction.self)

    /// Creates a `TestAction`.
    public init() {}

    /// Configuration for the test action.
    public struct Options: Codable, Sendable {
        /// Xcode scheme containing the test targets.
        public var scheme: String?

        /// Simulator destination (e.g. `"iPhone 16"`, `"iPad Pro (13-inch)"`).
        public var destination: String?

        /// Build configuration. Default: `Debug`.
        public var configuration: String?

        /// Whether to enable code coverage collection.
        public var enableCodeCoverage: Bool?

        /// Path to write the JUnit XML test result file.
        public var resultBundlePath: String?

        /// Test plan name to run (if multiple plans exist).
        public var testPlan: String?

        /// Creates `Options` for the test action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            scheme: String? = nil,
            destination: String? = nil,
            configuration: String? = nil,
            enableCodeCoverage: Bool? = nil,
            resultBundlePath: String? = nil,
            testPlan: String? = nil
        ) {
            self.scheme = scheme
            self.destination = destination
            self.configuration = configuration
            self.enableCodeCoverage = enableCodeCoverage
            self.resultBundlePath = resultBundlePath
            self.testPlan = testPlan
        }
    }

    /// Result of a test run.
    public struct Result: Codable, Sendable {
        /// Number of passing tests.
        public let passCount: Int

        /// Number of failing tests.
        public let failCount: Int

        /// Number of skipped tests.
        public let skipCount: Int

        /// Path to the `.xcresult` bundle.
        public let resultBundlePath: String?

        /// Whether all tests passed.
        public var succeeded: Bool { failCount == 0 }

        /// Creates a `Result`.
        public init(passCount: Int = 0, failCount: Int = 0, skipCount: Int = 0, resultBundlePath: String? = nil) {
            self.passCount = passCount
            self.failCount = failCount
            self.skipCount = skipCount
            self.resultBundlePath = resultBundlePath
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(reason: "Test requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme.")
        }

        let destination = options.destination ?? "platform=iOS Simulator,name=iPhone 16"
        let configuration = options.configuration ?? "Debug"

        logger.info("Testing scheme '\(scheme)' on '\(destination)'")

        var xcodeBuild = XcodeBuild(context: context.shell)
            .option(.scheme(scheme))
            .option(.configuration(configuration))
            .option(.destination(destination))
            .trailingArgument("test")

        if let workspace = context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        if options.enableCodeCoverage == true {
            xcodeBuild = xcodeBuild.option(.enableCodeCoverage("YES"))
        }

        if let resultPath = options.resultBundlePath {
            xcodeBuild = xcodeBuild.option(.resultBundlePath(resultPath))
        }

        if let testPlan = options.testPlan {
            xcodeBuild = xcodeBuild.option(.testPlan(testPlan))
        }

        let output = try await xcodeBuild.run()

        if output.exitCode != 0 {
            let failCount = parseFailureCount(from: output.stdout)
            logger.error("Tests failed with \(failCount) failure(s)")
            throw ShipItError.testFailed(exitCode: Int(output.exitCode), failureCount: failCount, log: output.stdout + output.stderr)
        }

        let passCount = parsePassCount(from: output.stdout)
        logger.info("Tests passed: \(passCount)")

        return Result(
            passCount: passCount,
            failCount: 0,
            skipCount: parseSkipCount(from: output.stdout),
            resultBundlePath: options.resultBundlePath
        )
    }

    // MARK: - Private Helpers

    private func parseFailureCount(from output: String) -> Int {
        // Parse "** TEST FAILED ** (X failures)"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("TEST FAILED") {
                // Try to extract a count
                let words = line.components(separatedBy: " ")
                for (i, word) in words.enumerated() {
                    if word == "failures)" || word == "failure)" {
                        if i > 0, let count = Int(words[i - 1].trimmingCharacters(in: .init(charactersIn: "("))) {
                            return count
                        }
                    }
                }
                return 1
            }
        }
        return 0
    }

    private func parsePassCount(from output: String) -> Int {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Executed") && line.contains("test") {
                let words = line.components(separatedBy: " ")
                if let executedIndex = words.firstIndex(of: "Executed"),
                   words.indices.contains(executedIndex + 1),
                   let count = Int(words[executedIndex + 1]) {
                    return count
                }
            }
        }
        return 0
    }

    private func parseSkipCount(from output: String) -> Int {
        output.components(separatedBy: "\n")
            .filter { $0.contains("skipped") }
            .count
    }
}

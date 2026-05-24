import Foundation

/// Input metadata passed to artifact locators before parsing.
public struct TestParseContext: Codable, Sendable, Hashable {
    public let platform: String?
    public let runner: String?
    public let preferredSources: [String]

    public init(platform: String? = nil, runner: String? = nil, preferredSources: [String] = []) {
        self.platform = platform
        self.runner = runner
        self.preferredSources = preferredSources
    }
}

/// Artifact discovered by a ``TestArtifactLocator``.
public struct TestArtifact: Codable, Sendable, Hashable {
    public let kind: TestArtifactKind
    public let path: String
    public let platform: String?
    public let runner: String?

    public init(kind: TestArtifactKind, path: String, platform: String? = nil, runner: String? = nil) {
        self.kind = kind
        self.path = path
        self.platform = platform
        self.runner = runner
    }
}

/// Canonical artifact kind used by parser selection.
public enum TestArtifactKind: String, Codable, Sendable {
    case xcresult
    case junitXML
    case jestJSON
    case flutterMachineJSON
    case text
}

/// Parses one runner-specific input into a normalized ``ParsedTestRun``.
public protocol TestResultParser: Sendable {
    associatedtype Input: Sendable

    /// Parses the provided input into a normalized test run.
    func parse(_ input: Input) async throws -> ParsedTestRun
}

/// Discovers parseable test artifacts from a project directory.
public protocol TestArtifactLocator: Sendable {
    /// Returns candidate artifacts in preference order.
    func locate(in projectRoot: String, context: TestParseContext) async throws -> [TestArtifact]
}

/// Builds runner-specific rerun selectors from a parsed run.
public protocol TestRerunPlanner: Sendable {
    /// Returns selectors for failed tests that support targeted reruns.
    func selectorsToRerun(from run: ParsedTestRun) -> [TestRerunSelector]
}

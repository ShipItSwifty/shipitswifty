import Foundation
import SwiftyShell

/// Checks Swift formatting without rewriting source files.
///
/// ## Usage
/// ```swift
/// try await SwiftFormatAction().run(with: .init(paths: ["Sources", "Tests"]), context: context)
/// ```
public struct SwiftFormatAction: Action {
    public static let name = "swift-format"
    public static let description = "Strict recursive Swift formatting lint"
    public init() {}
    public struct Options: Codable, Sendable {
        public var paths: [String]?
        public var configuration: String?
        public var reportPath: String?
        public init(paths: [String]? = nil, configuration: String? = nil, reportPath: String? = nil) {
            self.paths = paths
            self.configuration = configuration
            self.reportPath = reportPath
        }
    }
    public struct Result: Codable, Sendable {
        public let exitCode: Int
        public let reportPath: String?
    }
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let output: ShellOutput
        do {
            output = try await SwiftPMCLI(context: context.shell).formatLint(
                paths: options.paths ?? ["Sources", "Tests"], configuration: options.configuration
            ).run()
        } catch let ShellError.exitFailure(_, captured) { output = captured }
        if let path = options.reportPath {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (output.stdout + output.stderr).write(to: url, atomically: true, encoding: .utf8)
        }
        if output.exitCode != 0 { throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: output.stdout + output.stderr) }
        return .init(exitCode: Int(output.exitCode), reportPath: options.reportPath)
    }
}

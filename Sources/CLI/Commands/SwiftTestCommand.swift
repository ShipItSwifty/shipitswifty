import ArgumentParser
import Foundation
import ShipItKit

struct SwiftTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-test", abstract: "Run package tests with structured evidence and retries")
    @OptionGroup var global: GlobalOptions
    @Option(name: .long) var packagePath: String = "."
    @Option(name: .long) var scratchPath: String?
    @Option(name: .long) var filter: String?
    @Option(name: .long) var skip: String?
    @Option(name: .long) var outputDirectory: String?
    @Flag(name: .long) var codeCoverage: Bool = false
    @Flag(name: .long) var rerunFailedTests: Bool = false
    @Option(name: .long) var maxRerunAttempts: Int = 2
    @Option(name: .customLong("env"), help: "Test environment KEY=VALUE (repeatable)") var environment: [String] = []
    @Option(name: .long, help: "Total infrastructure attempts; omit to disable") var infrastructureAttempts: Int?
    func run() async throws {
        var values: [String: String] = [:]
        for entry in environment {
            guard let separator = entry.firstIndex(of: "="), separator != entry.startIndex else {
                throw ValidationError("--env requires KEY=VALUE")
            }
            values[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        if let infrastructureAttempts, infrastructureAttempts < 1 { throw ValidationError("--infrastructure-attempts must be positive") }
        if global.dryRun {
            try outputDryRun(action: "swift-test", message: "Would test package \(packagePath)", global: global)
            return
        }
        let context = try await buildFallbackActionContext(platform: global.platform ?? .android, verbose: global.verbose)
        do {
            let result = try await SwiftTestAction().run(
                with: .init(
                    packagePath: packagePath, scratchPath: scratchPath,
                    filter: filter, skip: skip, environment: values, enableCodeCoverage: codeCoverage, outputDirectory: outputDirectory,
                    rerunFailedTests: rerunFailedTests ? .init(enabled: true, maxAttempts: maxRerunAttempts) : nil,
                    infrastructureRetry: infrastructureAttempts.map { .init(maxAttempts: $0) }), context: context)
            outputResult(action: "swift-test", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
struct SwiftFormatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swift-format", abstract: "Check Swift formatting without rewriting files")
    @OptionGroup var global: GlobalOptions
    @Argument var paths: [String] = []
    @Option(name: .long) var configuration: String?
    @Option(name: .long) var reportPath: String?
    func run() async throws {
        if global.dryRun {
            try outputDryRun(action: "swift-format", message: "Would lint Swift formatting", global: global)
            return
        }
        let context = try await buildFallbackActionContext(platform: global.platform ?? .android, verbose: global.verbose)
        let result = try await SwiftFormatAction().run(
            with: .init(paths: paths.isEmpty ? nil : paths, configuration: configuration, reportPath: reportPath), context: context)
        outputResult(action: "swift-format", result: result, format: global.output, colorMode: global.effectiveColorMode)
    }
}

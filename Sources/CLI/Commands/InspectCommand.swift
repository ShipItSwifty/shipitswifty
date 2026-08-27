import ArgumentParser
import Foundation
import ShipItKit

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect the current project for AI-assisted config generation",
        subcommands: [Project.self]
    )
}

extension InspectCommand {
    struct Project: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "project",
            abstract: "Inspect Xcode containers, schemes, and release-related files"
        )

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Root path to inspect")
        var path: String = FileManager.default.currentDirectoryPath

        func run() async throws {
            let inspection = try await ProjectInspector(rootPath: path).inspect()

            switch global.output {
            case .json:
                let reporter = JSONReporter()
                print(
                    try reporter.encode(
                        ActionResultEnvelope(action: "inspect", status: "success", payload: projectInspectionJSON(inspection))))
            case .human:
                let formatter = makeHumanFormatter(global: global)
                formatter.printHeader("Project Inspection")
                formatter.printKV("Root", inspection.rootPath)
                formatter.printKV("Detected Platform", inspection.detectedPlatform.rawValue)
                formatter.printKV("Detected Build System", inspection.detectedBuildSystem?.rawValue ?? "native")
                if !inspection.buildSystemFiles.isEmpty {
                    formatter.printKV("Build System Files", inspection.buildSystemFiles.joined(separator: ", "))
                }
                formatter.printKV("Containers", String(inspection.xcodeContainers.count))
                if let preferred = inspection.preferredContainer {
                    formatter.printKV("Preferred", "\(preferred.kind): \(preferred.path)")
                }
                formatter.printKV("Schemes", inspection.schemes.isEmpty ? "(none)" : inspection.schemes.map(\.name).joined(separator: ", "))
                formatter.printKV("Test Plans", inspection.testPlans.isEmpty ? "(none)" : inspection.testPlans.joined(separator: ", "))
                if let scheme = inspection.suggestedAppConfig.scheme {
                    formatter.printKV("Suggested Scheme", scheme)
                }
                if let bundleID = inspection.suggestedAppConfig.bundleID {
                    formatter.printKV("Suggested Bundle ID", bundleID)
                }
                if let teamID = inspection.suggestedAppConfig.teamID {
                    formatter.printKV("Suggested Team ID", teamID)
                }
                for warning in inspection.warnings {
                    formatter.printWarning(warning)
                }
            }
        }
    }
}

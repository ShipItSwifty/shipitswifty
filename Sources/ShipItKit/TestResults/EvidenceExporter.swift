import Foundation
import SwiftyShell

/// One portable evidence file or directory. Paths are relative to the export directory.
public struct EvidenceEntry: Codable, Sendable, Hashable {
    public let kind: String
    public let path: String
    public let source: String
    public let testID: String?
    public init(kind: String, path: String, source: String, testID: String? = nil) {
        self.kind = kind
        self.path = path
        self.source = source
        self.testID = testID
    }
}

/// Portable evidence index shared by CLI inspection and workflow collection.
public struct EvidenceManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let entries: [EvidenceEntry]
    public let diagnostics: [ParsingDiagnostic]
    public init(entries: [EvidenceEntry], diagnostics: [ParsingDiagnostic] = []) {
        schemaVersion = 1
        self.entries = entries
        self.diagnostics = diagnostics
    }
}

/// Exports normalized results and original evidence without changing source artifacts.
public struct EvidenceExporter: Sendable {
    public let shell: ShellContext
    public init(shell: ShellContext) { self.shell = shell }

    public func export(
        runs: [ParsedTestRun], sources: [String], coverage: [CoverageAction.Result] = [],
        evidence: [String] = [], to directory: String
    ) async throws -> EvidenceManifest {
        let root = URL(fileURLWithPath: directory).standardizedFileURL
        // An export must be new: never remove user files or overwrite evidence from another run.
        if FileManager.default.fileExists(atPath: root.path) {
            throw ShipItError.invalidConfiguration(reason: "Export directory already exists: \(directory). Choose a new directory.")
        }
        let allSources = sources + evidence + coverage.map(\.source)
        for source in allSources {
            let url = URL(fileURLWithPath: source).standardizedFileURL
            guard !root.path.hasPrefix(url.path + "/"), root != url else {
                throw ShipItError.invalidConfiguration(reason: "Export directory must be outside its source: \(source)")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var entries: [EvidenceEntry] = []
        var diagnostics: [ParsingDiagnostic] = []
        for (index, source) in allSources.enumerated() {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: source) else {
                diagnostics.append(.init(severity: .warning, message: "Evidence unavailable", source: source))
                continue
            }
            let relative = "originals/\(index + 1)/\(URL(fileURLWithPath: source).lastPathComponent)"
            let target = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: source, toPath: target.path)
            entries.append(.init(kind: "original", path: relative, source: source))
            #if os(macOS)
            if source.hasSuffix(".xcresult") {
                let prefix = "extracted/\(index + 1)"
                for kind in ["attachments", "diagnostics"] {
                    do {
                        let output = root.appendingPathComponent("\(prefix)/\(kind)")
                        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                        _ = try await XCResultEvidenceTool(shell: shell).export(kind, from: source, to: output.path).run(in: shell)
                        entries.append(.init(kind: kind, path: "\(prefix)/\(kind)", source: source))
                        if kind == "attachments", let data = try? Data(contentsOf: output.appendingPathComponent("manifest.json")),
                            let tests = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                        {
                            for test in tests {
                                for attachment in test["attachments"] as? [[String: Any]] ?? [] {
                                    guard let file = attachment["exportedFileName"] as? String,
                                        !file.contains("/"), !file.contains("\\"), file != ".."
                                    else { continue }
                                    let dimensions = [attachment["configurationName"] as? String, attachment["deviceName"] as? String]
                                        .compactMap { $0 }
                                    let testID = (test["testIdentifier"] as? String).map {
                                        "xcresult-case:" + $0 + (dimensions.isEmpty ? "" : ":" + dimensions.joined(separator: ":"))
                                    }
                                    entries.append(
                                        .init(
                                            kind: file.hasSuffix(".png") || file.hasSuffix(".jpg") ? "screenshot" : "attachment",
                                            path: "\(prefix)/attachments/\(file)", source: source, testID: testID))
                                }
                            }
                        }
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw error }
                        diagnostics.append(.init(severity: .warning, message: "\(kind) unavailable: \(error)", source: source))
                    }
                }
                for kind in ["build", "action", "console"] {
                    do {
                        let output = try await XCResultEvidenceTool(shell: shell).log(kind, from: source).run(in: shell)
                        let relative = "\(prefix)/\(kind)-log.json"
                        try output.stdout.write(to: root.appendingPathComponent(relative), atomically: true, encoding: .utf8)
                        entries.append(.init(kind: "log", path: relative, source: source))
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw error }
                        diagnostics.append(.init(severity: .warning, message: "\(kind) log unavailable: \(error)", source: source))
                    }
                }
            }
            #endif
        }
        try write(runs, to: root.appendingPathComponent("results.json"))
        try write(coverage, to: root.appendingPathComponent("coverage.json"))
        let manifest = EvidenceManifest(entries: entries, diagnostics: diagnostics)
        try write(manifest, to: root.appendingPathComponent("manifest.json"))
        var index = "# Test evidence\n\n[Results](results.json) · [Coverage](coverage.json) · [Manifest](manifest.json)\n\n"
        for run in runs {
            index +=
                "- \(run.runner): \(run.summary.passed) passed, \(run.summary.failed) failed, \(run.summary.errored) errored, \(run.summary.skipped) skipped\n"
        }
        index += "\n"
        for entry in entries {
            index += "- [\(entry.kind)](\(entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path))\n"
        }
        try index.write(to: root.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        return manifest
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

#if os(macOS)
/// Typed xcresulttool evidence commands. Extraction never runs tests.
struct XCResultEvidenceTool: Sendable {
    let shell: ShellContext
    func export(_ kind: String, from path: String, to output: String) -> Command {
        Xcrun(context: shell).tool("xcresulttool").trailingArguments(["export", kind, "--path", path, "--output-path", output]).command()
    }
    func log(_ kind: String, from path: String) -> Command {
        Xcrun(context: shell).tool("xcresulttool").trailingArguments(["get", "log", "--path", path, "--type", kind, "--compact"]).command()
    }
}
#endif

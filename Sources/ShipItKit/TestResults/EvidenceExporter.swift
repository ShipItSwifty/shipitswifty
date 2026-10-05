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

/// The versioned envelope written to `results.json` in an export.
struct ExportedResults: Codable, Sendable {
    let schemaVersion: Int
    let runs: [ParsedTestRun]
    init(runs: [ParsedTestRun]) {
        schemaVersion = 1
        self.runs = runs
    }
}

/// The versioned envelope written to `coverage.json` in an export. Reports are kept side by side with their
/// provenance; they are never summed, because overlapping or selective-rerun coverage would mislead.
struct ExportedCoverage: Codable, Sendable {
    let schemaVersion: Int
    let coverage: [CoverageAction.Result]
    init(coverage: [CoverageAction.Result]) {
        schemaVersion = 1
        self.coverage = coverage
    }
}

/// Exports normalized results and original evidence without changing source artifacts.
///
/// The export is assembled in a hidden sibling directory and renamed into place only when complete, so a
/// failed or cancelled export leaves nothing behind and the same directory can be used again.
public struct EvidenceExporter: Sendable {
    public let shell: ShellContext
    public init(shell: ShellContext) { self.shell = shell }

    public func export(
        runs: [ParsedTestRun], sources: [String], coverage: [CoverageAction.Result] = [],
        evidence: [String] = [], to directory: String
    ) async throws -> EvidenceManifest {
        let destination = URL(fileURLWithPath: directory).standardizedFileURL
        // An export must be new: never remove user files or overwrite evidence from another run.
        if FileManager.default.fileExists(atPath: destination.path) {
            throw ShipItError.invalidConfiguration(reason: "Export directory already exists: \(directory). Choose a new directory.")
        }
        let allSources = sources + evidence + coverage.map(\.source)
        for source in allSources {
            let url = URL(fileURLWithPath: source).standardizedFileURL
            guard !destination.path.hasPrefix(url.path + "/"), destination != url else {
                throw ShipItError.invalidConfiguration(reason: "Export directory must be outside its source: \(source)")
            }
        }
        // Same parent, so the final rename stays on one volume and is atomic.
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let manifest = try await assemble(
                into: root, runs: runs, allSources: allSources, coverage: coverage)
            try Task.checkCancellation()
            do { try FileManager.default.moveItem(at: root, to: destination) } catch {
                // Someone created the destination while the export ran; their files are not ours to replace.
                throw ShipItError.invalidConfiguration(reason: "Could not create export directory \(directory): \(error)")
            }
            return manifest
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func assemble(
        into root: URL, runs: [ParsedTestRun], allSources: [String], coverage: [CoverageAction.Result]
    ) async throws -> EvidenceManifest {
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
            // Links are followed: an export must hold the evidence itself, not pointers that dangle once it moves.
            var skipped: [String] = []
            try copyFollowingLinks(URL(fileURLWithPath: source), to: target, ancestors: []) { skipped.append($0) }
            diagnostics += skipped.map { .init(severity: .warning, message: "Skipped a link that does not resolve", source: $0) }
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
        try write(ExportedResults(runs: runs), to: root.appendingPathComponent("results.json"))
        try write(ExportedCoverage(coverage: coverage), to: root.appendingPathComponent("coverage.json"))
        let manifest = EvidenceManifest(entries: entries, diagnostics: diagnostics)
        try write(manifest, to: root.appendingPathComponent("manifest.json"))
        try indexMarkdown(runs: runs, coverage: coverage, entries: entries)
            .write(to: root.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        return manifest
    }

    private func indexMarkdown(runs: [ParsedTestRun], coverage: [CoverageAction.Result], entries: [EvidenceEntry]) -> String {
        var index = "# Test evidence\n\n[Results](results.json) · [Coverage](coverage.json) · [Manifest](manifest.json)\n\n"
        for run in runs {
            index +=
                "- \(run.runner): \(run.summary.passed) passed, \(run.summary.failed) failed, \(run.summary.errored) errored, \(run.summary.skipped) skipped\n"
        }
        if !coverage.isEmpty {
            index += "\n## Coverage\n\n"
            for report in coverage {
                let percent = String(format: "%.1f%%", report.overallLineCoverage)
                index +=
                    "- \(URL(fileURLWithPath: report.source).lastPathComponent) (\(report.platform)): \(percent), \(report.coveredLines) of \(report.executableLines) lines\n"
            }
            index += "\nReports are listed separately and never summed: overlapping or partial reports would overstate coverage.\n"
        }
        index += "\n"
        for entry in entries {
            index += "- [\(entry.kind)](\(entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path))\n"
        }
        return index
    }

    /// Copies `source` to `target`, following symbolic links so the copy holds real files. Directory cycles are
    /// cut, and a nested link that does not resolve is reported through `skipped` instead of failing the export.
    private func copyFollowingLinks(_ source: URL, to target: URL, ancestors: Set<String>, skipped: (String) -> Void) throws {
        try Task.checkCancellation()
        let resolved = source.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            skipped(source.path)
            return
        }
        guard isDirectory.boolValue else {
            try FileManager.default.copyItem(at: resolved, to: target)
            return
        }
        guard !ancestors.contains(resolved.path) else { return }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: resolved.path).sorted() {
            try copyFollowingLinks(
                resolved.appendingPathComponent(name), to: target.appendingPathComponent(name),
                ancestors: ancestors.union([resolved.path]), skipped: skipped)
        }
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

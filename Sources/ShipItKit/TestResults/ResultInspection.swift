import Foundation
import Logging
import SwiftyShell

/// Artifact encoding, independent of the platform that executed the tests.
public enum TestInputFormat: String, Codable, Sendable {
    case xcresult, junit, flutter, jest, swift, shipit, manifest
}

/// Shared reader used by offline inspection and test lanes.
///
/// ## Usage
/// ```swift
/// let run = try await ResultInspection(shell: context.shell).read("results.xml", format: .junit)
/// ```
public struct ResultInspection: Sendable {
    public let shell: ShellContext
    public init(shell: ShellContext) { self.shell = shell }

    public func read(_ path: String, format: TestInputFormat? = nil, runner: String? = nil) async throws -> ParsedTestRun {
        let kind = try format ?? detect(path)
        let run: ParsedTestRun
        switch kind {
        case .xcresult:
            #if os(macOS)
            run = try await IOSXCResultTestParser(shell: shell).parse(xcresultPath: path)
            #else
            throw ShipItError.invalidConfiguration(reason: "iOS test-result parsing requires macOS.")
            #endif
        case .junit:
            run = try await AndroidJUnitTestParser().parse(
                reportDirectory: path,
                platform: runner == "kmp" ? "kmp" : runner == "swift-test" ? "swift" : "android", runner: runner ?? "gradle",
                identityRoot: gradleProjectRoot(containing: path))
        case .flutter:
            run = try await FlutterMachineOutputParser().parse(machineOutput: String(contentsOfFile: path, encoding: .utf8))
        case .jest:
            run = try await JestJSONTestParser().parse(jsonFilePath: path)
        case .swift:
            run = try SwiftEventParser().parse(path: path)
        case .manifest:
            let url = URL(fileURLWithPath: path)
            let root =
                url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                ? url : url.deletingLastPathComponent()
            let data = try Data(contentsOf: root.appendingPathComponent("results.json"))
            let runs = try JSONDecoder().decode(ExportedResults.self, from: data).runs
            guard !runs.isEmpty else { throw ShipItError.invalidConfiguration(reason: "Export contains no normalized results") }
            return ParsedTestRun(
                platform: runs.count == 1 ? runs[0].platform : "mixed", runner: runs.count == 1 ? runs[0].runner : "multiple", source: path,
                summary: .init(
                    passed: runs.reduce(0) { $0 + $1.summary.passed }, failed: runs.reduce(0) { $0 + $1.summary.failed },
                    skipped: runs.reduce(0) { $0 + $1.summary.skipped }, flaky: runs.reduce(0) { $0 + $1.summary.flaky },
                    errored: runs.reduce(0) { $0 + $1.summary.errored }),
                testCases: runs.enumerated().flatMap { index, run in
                    run.testCases.map { $0.copy(stableID: "input-\(index + 1):" + $0.stableID) }
                }, diagnostics: runs.flatMap(\.diagnostics))
        case .shipit:
            var file = URL(fileURLWithPath: path)
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                file = file.appendingPathComponent(
                    FileManager.default.fileExists(atPath: file.appendingPathComponent("report.json").path) ? "report.json" : "results.json"
                )
            }
            if let run = try? JSONDecoder().decode(ParsedTestRun.self, from: Data(contentsOf: file)) { return run }
            let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: file))
            return ParsedTestRun(
                platform: report.platform, runner: report.runner, source: path, summary: report.summary,
                testCases: report.testCases ?? (report.persistentFailedTests + report.flakyTests))
        }
        // Parsed artifacts must report at least one outcome. An empty or unreadable run is an error here, not a
        // successful zero-test run.
        guard run.hasResults else {
            throw ShipItError.invalidConfiguration(
                reason: "No test results found in '\(path)'" + (run.diagnostics.first.map { ": \($0.message)" } ?? "."))
        }
        return ParsedTestRun(
            platform: run.platform, runner: runner ?? run.runner, source: path, summary: run.summary,
            suites: run.suites, testCases: run.testCases, diagnostics: run.diagnostics)
    }

    /// The nearest enclosing Gradle project (a directory with `settings.gradle[.kts]` or `gradlew`), used so
    /// offline test identities match the ones a live run computes relative to the project directory.
    /// `nil` when the artifact lives outside any project, such as a relocated export.
    func gradleProjectRoot(containing path: String) -> String? {
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        if !(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            directory.deleteLastPathComponent()
        }
        while directory.path != "/" {
            for marker in ["settings.gradle.kts", "settings.gradle", "gradlew"]
            where FileManager.default.fileExists(atPath: directory.appendingPathComponent(marker).path) {
                return directory.path
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    public func detect(_ path: String) throws -> TestInputFormat {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension == "xcresult" { return .xcresult }
        if url.pathExtension == "xml" { return .junit }
        if url.pathExtension == "jsonl" || url.pathExtension == "ndjson" {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            if text.components(separatedBy: .newlines).prefix(10).contains(where: {
                $0.contains("\"payload\"") && $0.contains("\"version\"")
            }) {
                return .swift
            }
            return .flutter
        }
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path),
                FileManager.default.fileExists(atPath: url.appendingPathComponent("results.json").path)
            {
                return .manifest
            }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("report.json").path) { return .shipit }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("results.json").path) { return .shipit }
            let xml = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).contains {
                $0.pathExtension == "xml"
            }
            if xml { return .junit }
        }
        if let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if object["entries"] != nil || object["runs"] != nil, object["schemaVersion"] != nil { return .manifest }
            if object["testCases"] != nil, object["summary"] != nil { return .shipit }
            if object["testResults"] != nil { return .jest }
            if object["attempts"] != nil, object["schemaVersion"] != nil { return .shipit }
        }
        throw ShipItError.invalidConfiguration(
            reason: "Ambiguous result input '\(path)'; specify input_format (xcresult, junit, flutter, jest, swift, shipit, manifest).")
    }
}

/// Coverage encoding supported by portable inspection.
public enum CoverageInputFormat: String, Codable, Sendable { case lcov, swift, jacoco, kover }

/// Reads file-based coverage without running tests. Overlapping files are merged by line identity.
public struct PortableCoverageReader: Sendable {
    public init() {}
    public func read(
        _ path: String, format: CoverageInputFormat, sourceRoots: [String] = [], excludePreviews: Bool = false
    ) async throws -> CoverageAction.Result {
        if format == .jacoco || format == .kover {
            let targets = try await AndroidCoverageParser(logger: Logger(label: "shipit.coverage")).parse(reportPath: path)
            guard targets.reduce(0, { $0 + $1.executableLines }) > 0 else {
                throw ShipItError.invalidConfiguration(reason: "No executable coverage lines found in \(path)")
            }
            return result(path: path, platform: "jvm", targets: targets)
        }
        var lines: [String: [Int: Int]] = [:]
        if format == .lcov {
            var file: String?
            for line in try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines) {
                if line.hasPrefix("SF:") { file = String(line.dropFirst(3)) }
                if line == "end_of_record" { file = nil }
                if line.hasPrefix("DA:"), let file {
                    let values = line.dropFirst(3).split(separator: ",")
                    guard values.count >= 2, let number = Int(values[0]), let count = Int(values[1]) else {
                        throw ShipItError.invalidConfiguration(reason: "Malformed LCOV line: \(line)")
                    }
                    lines[file, default: [:]][number] = max(lines[file]?[number] ?? 0, count)
                }
            }
        } else {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let entries = object["data"] as? [[String: Any]]
            else {
                throw ShipItError.invalidConfiguration(reason: "Invalid SwiftPM/LLVM coverage JSON at \(path)")
            }
            for entry in entries {
                for file in entry["files"] as? [[String: Any]] ?? [] {
                    guard let name = file["filename"] as? String, let segments = file["segments"] as? [[Any]] else { continue }
                    struct Segment {
                        let line: Int
                        let count: Int
                        let hasCount: Bool
                        let entry: Bool
                        let gap: Bool
                    }
                    let mapped = segments.compactMap { value -> Segment? in
                        guard value.count >= 5, let line = value[0] as? Int, let count = value[2] as? Int,
                            let hasCount = value[3] as? Bool, let entry = value[4] as? Bool
                        else { return nil }
                        return .init(
                            line: line, count: count, hasCount: hasCount, entry: entry,
                            gap: value.count > 5 ? value[5] as? Bool ?? false : false)
                    }
                    guard let first = mapped.first, let last = mapped.last, first.line <= last.line else { continue }
                    var cursor = 0
                    var wrapped: Segment?
                    // Match LLVM's LineCoverageStats: region entries and the preceding wrapped segment
                    // determine whether a line is executable; gap regions do not raise its count.
                    for number in first.line...last.line {
                        var current: [Segment] = []
                        while cursor < mapped.count, mapped[cursor].line == number {
                            current.append(mapped[cursor])
                            cursor += 1
                        }
                        let entries = current.filter { $0.hasCount && $0.entry && !$0.gap }
                        let skipped = current.first.map { !$0.hasCount && $0.entry } ?? false
                        let executable =
                            (!skipped && (wrapped?.hasCount == true || !entries.isEmpty)) || current.contains { $0.entry && $0.hasCount }
                        if executable {
                            let count = max(wrapped?.count ?? 0, entries.map(\.count).max() ?? 0)
                            lines[name, default: [:]][number] = max(lines[name]?[number] ?? 0, count)
                        }
                        if let last = current.last { wrapped = last }
                    }
                }
            }
        }
        let files: [CoverageFile] = try lines.keys.sorted().compactMap { path in
            if !sourceRoots.isEmpty
                && !sourceRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") || path.contains("/" + $0 + "/") })
            {
                return nil
            }
            var counts = lines[path] ?? [:]
            if excludePreviews {
                let contents = try String(contentsOfFile: path, encoding: .utf8)
                if let index = contents.components(separatedBy: .newlines).firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix("#Preview")
                }) {
                    counts = counts.filter { $0.key < index + 1 }
                }
            }
            let covered = counts.values.filter { $0 > 0 }.count
            return CoverageFile(
                path: path, lineCoverage: counts.isEmpty ? 0 : Double(covered) * 100 / Double(counts.count), coveredLines: covered,
                executableLines: counts.count)
        }
        let covered = files.reduce(0) { $0 + $1.coveredLines }
        let executable = files.reduce(0) { $0 + $1.executableLines }
        guard executable > 0 else { throw ShipItError.invalidConfiguration(reason: "No executable coverage lines found in \(path).") }
        let target = CoverageTarget(
            name: format == .swift ? "package" : "flutter", lineCoverage: Double(covered) * 100 / Double(executable), coveredLines: covered,
            executableLines: executable, files: files)
        return result(path: path, platform: format == .swift ? "swift" : "flutter", targets: [target])
    }
    private func result(path: String, platform: String, targets: [CoverageTarget]) -> CoverageAction.Result {
        let covered = targets.reduce(0) { $0 + $1.coveredLines }
        let total = targets.reduce(0) { $0 + $1.executableLines }
        return .init(
            platform: platform, source: path, overallLineCoverage: total == 0 ? 0 : Double(covered) * 100 / Double(total), targets: targets,
            coveredLines: covered, executableLines: total, firstPartyOnly: false)
    }
}

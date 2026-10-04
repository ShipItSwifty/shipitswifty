import Foundation

/// Evidence exported after a workflow step, even when that step fails.
public struct ArtifactDeclaration: Codable, Sendable {
    public let name: String
    public let paths: [String]
    public let retentionDays: Int?
    public init(name: String, paths: [String], retentionDays: Int? = nil) {
        self.name = name
        self.paths = paths
        self.retentionDays = retentionDays
    }
    enum CodingKeys: String, CodingKey {
        case name, paths
        case retentionDays = "retention_days"
    }
}

/// The persisted outcome of one step's evidence collection.
public struct WorkflowArtifactRecord: Codable, Sendable {
    public let step: String
    public let action: String
    public let status: String
    public let entries: [EvidenceEntry]
    public let diagnostics: [ParsingDiagnostic]
}

/// Synchronous collection used from structured workflow execution and composite actions.
func collectWorkflowArtifacts(
    step: String, action: String, declarations: [ArtifactDeclaration], payload: JSONValue?,
    status: String, root: String
) throws {
    var entries: [EvidenceEntry] = []
    var diagnostics: [ParsingDiagnostic] = []
    let directory = URL(fileURLWithPath: root).appendingPathComponent(step)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var declared = declarations
    let automatic = artifactPaths(payload, excluding: URL(fileURLWithPath: root).standardizedFileURL.path)
    if !automatic.isEmpty { declared.append(.init(name: "outputs", paths: automatic)) }
    for declaration in declared {
        guard !declaration.name.isEmpty, declaration.name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw ShipItError.invalidConfiguration(reason: "Artifact name must contain only letters, numbers, _ or -")
        }
        if let days = declaration.retentionDays, !(1...90).contains(days) {
            throw ShipItError.invalidConfiguration(reason: "Artifact retention_days must be 1...90")
        }
        for (patternIndex, pattern) in declaration.paths.enumerated() {
            let matches = try artifactMatches(pattern)
            if matches.isEmpty { diagnostics.append(.init(severity: .warning, message: "No files match artifact path", source: pattern)) }
            for (index, source) in matches.enumerated() {
                let relative = "\(declaration.name)/\(patternIndex + 1)-\(index + 1)/\(source.lastPathComponent)"
                let target = directory.appendingPathComponent(relative)
                guard !target.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/") else {
                    diagnostics.append(.init(severity: .warning, message: "Skipped recursive artifact collection", source: pattern))
                    continue
                }
                // Evidence collection must not take down the step it describes: one unreadable file is a
                // diagnostic, and everything else is still collected.
                do {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: target)
                    entries.append(.init(kind: declaration.name, path: relative, source: source.path))
                } catch {
                    diagnostics.append(.init(severity: .warning, message: "Could not collect artifact: \(error)", source: source.path))
                }
            }
        }
    }
    try writeJSON(
        WorkflowArtifactRecord(step: step, action: action, status: status, entries: entries, diagnostics: diagnostics),
        to: directory.appendingPathComponent("manifest.json"))
}

/// Report and result locations a step publishes about itself. Deliberately excludes build products
/// (`ipaPath`, `aabPath`, `apkPath`, `archivePath`, `artifactPath`): copying signed binaries into evidence
/// that CI later uploads must be an explicit `artifacts:` declaration, never a side effect.
private let evidencePayloadKeys: Set<String> = [
    "reportPath", "outputDirectory", "resultBundlePath", "coveragePath",
    "report_path", "output_directory", "result_bundle_path", "coverage_path",
]

private func artifactPaths(_ payload: JSONValue?, excluding evidenceRoot: String) -> [String] {
    guard let payload else { return [] }
    switch payload {
    case .object(let object):
        return object.flatMap { key, value -> [String] in
            if evidencePayloadKeys.contains(key), let path = value.stringValue, FileManager.default.fileExists(atPath: path) {
                // Results already written under the evidence root are collected in place; copying them again
                // would double the stored evidence.
                let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
                if standardized == evidenceRoot || standardized.hasPrefix(evidenceRoot + "/") { return [] }
                return [path]
            }
            return artifactPaths(value, excluding: evidenceRoot)
        }
    case .array(let items): return items.flatMap { artifactPaths($0, excluding: evidenceRoot) }
    default: return []
    }
}

/// Splits an absolute glob at its first wildcard component.
private func splitGlob(_ fullPattern: String) -> (literal: [Substring], wildcard: [Substring]) {
    let components = fullPattern.split(separator: "/")
    let index = components.firstIndex { $0.contains("*") || $0.contains("?") } ?? components.endIndex
    return (Array(components[..<index]), Array(components[index...]))
}

/// The directory to walk for an absolute glob: the literal prefix that precedes the first wildcard component.
///
/// Stripping the last path component of the text before the wildcard would climb one level too far when it
/// ends in `/`, turning `<project>/*.log` into a walk of the filesystem root.
func artifactSearchRoot(for fullPattern: String) -> URL {
    URL(fileURLWithPath: "/" + splitGlob(fullPattern).literal.joined(separator: "/"), isDirectory: true)
}

func artifactMatches(_ pattern: String) throws -> [URL] {
    let full = URL(fileURLWithPath: pattern).standardizedFileURL.path
    guard full.contains("*") || full.contains("?") else {
        return FileManager.default.fileExists(atPath: full) ? [URL(fileURLWithPath: full)] : []
    }
    let ancestor = artifactSearchRoot(for: full)
    // Match on paths relative to the walked directory. Absolute paths are unreliable here: standardizing a
    // pattern drops `/private` from `/private/var/...`, but the enumerator reports the real location, so an
    // absolute comparison never matches anything under a symlinked prefix such as `/var` or `/tmp`.
    let wildcard = splitGlob(full).wildcard.joined(separator: "/")
    let regexText =
        "^"
        + NSRegularExpression.escapedPattern(for: wildcard)
        // `escapedPattern` escapes `/` too, so `**/` arrives as `\*\*\/`; it must match zero or more directories.
        .replacingOccurrences(of: "\\*\\*\\/", with: "(?:.*/)?")
        .replacingOccurrences(of: "\\*\\*", with: ".*")
        .replacingOccurrences(of: "\\*", with: "[^/]*")
        .replacingOccurrences(of: "\\?", with: "[^/]") + "$"
    let regex = try NSRegularExpression(pattern: regexText)
    guard let walker = FileManager.default.enumerator(at: ancestor, includingPropertiesForKeys: nil) else { return [] }
    var relatives: [String] = []
    while let url = walker.nextObject() as? URL {
        // `level` is the depth below `ancestor`, so the last `level` components are the relative path whatever
        // spelling (`/var` or `/private/var`) the enumerator reports for the prefix.
        let relative = url.pathComponents.suffix(walker.level).joined(separator: "/")
        if regex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil { relatives.append(relative) }
    }
    relatives.sort()
    // A directory match already contains its descendants.
    return relatives.filter { candidate in !relatives.contains { $0 != candidate && candidate.hasPrefix($0 + "/") } }
        .map { ancestor.appendingPathComponent($0) }
}

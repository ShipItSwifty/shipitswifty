import Foundation
import Logging
import SwiftyShell

/// Saves the coverage of the run that just finished as LLVM JSON at `target`.
///
/// SwiftPM writes its coverage JSON only when every test passed, so a run with a failure (a flaky test on its
/// first attempt, say) has none even though the raw profiles (`*.profraw`) were written. Those profiles are what
/// the JSON is computed from, so when the JSON is missing the coverage is recomputed from them with
/// `llvm-profdata` and `llvm-cov`. That must happen before any rerun: a rerun adds its own profiles to the same
/// directory, and its coverage covers only the tests it reran.
///
/// SwiftPM's swiftbuild driver also exports one test product at a time to the same JSON path, so when a package
/// has several test products they are exported together, to include every test target.
func saveSwiftPMCoverage(source: String, target: URL, shell: ShellContext) async throws {
    let json = URL(fileURLWithPath: source)
    let directory = json.deletingLastPathComponent()
    let binaries = swiftPMTestBinaries(in: directory.deletingLastPathComponent())
    let rawProfiles = swiftPMRawProfiles(in: directory)
    let defaultProfile = directory.appendingPathComponent("default.profdata")
    let hasJSON = FileManager.default.fileExists(atPath: json.path)

    if hasJSON && binaries.count <= 1 {
        try FileManager.default.copyItem(at: json, to: target)
        return
    }
    guard let first = binaries.first else {
        throw ShipItError.invalidConfiguration(reason: "SwiftPM produced no coverage JSON and no test binary to compute it from.")
    }
    let profile: URL
    if hasJSON, FileManager.default.fileExists(atPath: defaultProfile.path) {
        profile = defaultProfile
    } else {
        guard !rawProfiles.isEmpty else {
            throw ShipItError.invalidConfiguration(reason: "SwiftPM produced no coverage JSON and no raw profiles in \(directory.path).")
        }
        profile = target.deletingLastPathComponent().appendingPathComponent("initial.profdata")
        _ = try await llvm("llvm-profdata", ["merge", "-sparse"] + rawProfiles.map(\.path) + ["-o", profile.path], shell: shell)
    }
    var arguments = ["export", "-instr-profile", profile.path, first.path]
    for binary in binaries.dropFirst() { arguments += ["-object", binary.path] }
    let output = try await llvm("llvm-cov", arguments, shell: shell)
    try output.stdout.write(to: target, atomically: true, encoding: .utf8)
}

/// The test executables SwiftPM built: `.xctest` bundles on macOS, plain `.xctest` executables on Linux.
func swiftPMTestBinaries(in products: URL) -> [URL] {
    let items = (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []
    return items.filter { $0.pathExtension == "xctest" }.compactMap { item -> URL? in
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else { return item }
        let executable = item.appendingPathComponent("Contents/MacOS/" + item.deletingPathExtension().lastPathComponent)
        return FileManager.default.fileExists(atPath: executable.path) ? executable : nil
    }.sorted { $0.path < $1.path }
}

func swiftPMRawProfiles(in directory: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "profraw" }.sorted { $0.path < $1.path }
}

private func llvm(_ tool: String, _ arguments: [String], shell: ShellContext) async throws -> ShellOutput {
    #if os(macOS)
    try await Xcrun(context: shell).tool(tool).trailingArguments(arguments).run()
    #else
    try await Command(tool).args(arguments).run(in: shell)
    #endif
}

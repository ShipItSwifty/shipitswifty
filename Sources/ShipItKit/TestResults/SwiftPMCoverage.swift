import Foundation
import SwiftyShell

/// SwiftPM's swiftbuild driver exports one test product at a time to the same JSON path.
/// Export all products together so a package's coverage includes every test target.
func saveSwiftPMCoverage(source: String, target: URL, shell: ShellContext) async throws {
    let url = URL(fileURLWithPath: source)
    #if os(macOS)
    let products = url.deletingLastPathComponent().deletingLastPathComponent()
    let bundles = (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []
    let binaries = bundles.filter { $0.pathExtension == "xctest" }.map {
        $0.appendingPathComponent("Contents/MacOS/" + $0.deletingPathExtension().lastPathComponent)
    }.filter { FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.path < $1.path }
    let profile = url.deletingLastPathComponent().appendingPathComponent("default.profdata")
    if binaries.count > 1, FileManager.default.fileExists(atPath: profile.path), let first = binaries.first {
        var arguments = ["export", "-instr-profile", profile.path, first.path]
        for binary in binaries.dropFirst() { arguments += ["-object", binary.path] }
        let output = try await Xcrun(context: shell).tool("llvm-cov").trailingArguments(arguments).run()
        try output.stdout.write(to: target, atomically: true, encoding: .utf8)
        return
    }
    #endif
    try FileManager.default.copyItem(at: url, to: target)
}

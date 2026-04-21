import Foundation

/// Copies a fixture directory to a unique temp location, invokes `body` with the
/// copy's URL, then deletes the copy on exit.
///
/// Each real-build test (xcodebuild, Gradle) that runs against a shared fixture
/// directory must use this helper so concurrent test runs don't conflict on
/// derived data, Gradle project locks, or build output directories.
///
/// Usage:
/// ```swift
/// try await withFixtureCopy(of: FixturePaths.iosSample) { tmpDir in
///     let result = try await CLI.run("archive", workingDirectory: tmpDir, ...)
/// }
/// ```
func withFixtureCopy(
    of fixture: URL,
    body: (URL) async throws -> Void
) async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShipItTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.copyItem(at: fixture, to: tmp)
    try await body(tmp)
}

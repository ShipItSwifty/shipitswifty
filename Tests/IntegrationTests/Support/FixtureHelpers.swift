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

/// Copies a Shipfile into `directory` (typically a fixture copy) and returns the
/// destination URL.
///
/// ShipIt derives the project root from the Shipfile's own directory. When a test
/// runs a real build against a temp fixture copy, the Shipfile must live inside that
/// copy — otherwise the build runs in the original Shipfile's directory (e.g. a shared
/// `Shipfiles/` folder) which is not a buildable project. The copy uses a unique name
/// so it never collides with a Shipfile already present in the fixture.
func copiedShipfile(_ source: URL, into directory: URL) throws -> URL {
    let destination = directory.appendingPathComponent("Shipfile-\(UUID().uuidString).yml")
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
}

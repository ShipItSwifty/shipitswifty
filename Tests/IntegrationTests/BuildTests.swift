import Testing
import Foundation

/// Integration tests for the iOS build/archive pipeline against the fixture project.
///
/// Dry-run tests run on every machine. Real-build tests require the iOS simulator SDK
/// (available on any macOS machine with Xcode installed) but do not need credentials.
///
/// **Prerequisite:** Run `swift build` before running these tests.
@Suite("Build Integration")
struct BuildIntegrationTests {

    private let fixtureDir = FixturePaths.iosSample
    private let scheme = "ios-sample"
    private let archivePath: String = FileManager.default.temporaryDirectory
        .appendingPathComponent("ios-sample-\(Int.random(in: 1000...9999)).xcarchive")
        .path

    // MARK: - Dry-run (always runs)

    @Test("build --dry-run exits 0 and prints dry-run message")
    func buildDryRunExitsZero() async throws {
        try assertIOSFixtureExists()
        let result = try await CLI.run(
            "build", "--scheme", scheme, "--dry-run",
            workingDirectory: fixtureDir
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(
            result.stdout.lowercased().contains("dry run") ||
            result.stdout.lowercased().contains("would"),
            "Expected dry-run message, got: \(result.stdout)"
        )
    }

    @Test("archive --dry-run exits 0")
    func archiveDryRunExitsZero() async throws {
        try assertIOSFixtureExists()
        let result = try await CLI.run(
            "archive", "--scheme", scheme,
            "--output-path", archivePath,
            "--dry-run",
            workingDirectory: fixtureDir
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
    }

    // MARK: - Real builds (unsigned, no credentials needed)

    @Test("build compiles ios-sample against simulator SDK")
    func buildCompilesForSimulator() async throws {
        try assertIOSFixtureExists()
        let result = try await CLI.run(
            "build",
            "--scheme", scheme,
            "--configuration", "Debug",
            workingDirectory: fixtureDir,
            timeout: 300
        )
        #expect(result.exitCode == 0, "build failed:\n\(result.stderr)")
    }

    @Test("archive produces .xcarchive with expected structure")
    func archiveProducesXcarchive() async throws {
        try assertIOSFixtureExists()
        let tmpArchive = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-sample-\(UUID().uuidString).xcarchive")
        defer { try? FileManager.default.removeItem(at: tmpArchive) }

        let result = try await CLI.run(
            "archive",
            "--scheme", scheme,
            "--output-path", tmpArchive.path,
            workingDirectory: fixtureDir,
            timeout: 300
        )
        #expect(result.exitCode == 0, "archive failed:\n\(result.stderr)")

        // Verify archive structure
        let infoPlist = tmpArchive.appendingPathComponent("Info.plist")
        #expect(
            FileManager.default.fileExists(atPath: infoPlist.path),
            ".xcarchive missing Info.plist"
        )
        let products = tmpArchive.appendingPathComponent("Products")
        #expect(
            FileManager.default.fileExists(atPath: products.path),
            ".xcarchive missing Products directory"
        )
    }

    // MARK: - validate archive

    @Test("validate archive reports correct bundle ID")
    func validateArchiveReportsBundleID() async throws {
        try assertIOSFixtureExists()
        try assertIntegrationScope(shipfile: FixturePaths.iosBetaShipfile)

        // Build an archive from the ios-sample fixture so the test is self-contained.
        let tmpArchive = FileManager.default.temporaryDirectory
            .appendingPathComponent("validate-\(UUID().uuidString).xcarchive")
        defer { try? FileManager.default.removeItem(at: tmpArchive) }

        let archiveResult = try await CLI.run(
            "archive",
            "--scheme", scheme,
            "--output-path", tmpArchive.path,
            workingDirectory: fixtureDir,
            timeout: 300
        )
        try #require(archiveResult.exitCode == 0, "archive failed:\n\(archiveResult.stderr)")

        let validateResult = try await CLI.run(
            "validate", "archive",
            "--archive-path", tmpArchive.path,
            "--output", "json"
        )
        #expect(validateResult.exitCode == 0, "validate archive failed:\n\(validateResult.stderr)")

        // JSON output should mention the bundle ID
        #expect(
            validateResult.stdout.contains(integrationBundleID),
            "Expected bundle ID \(integrationBundleID) in output"
        )
    }
}

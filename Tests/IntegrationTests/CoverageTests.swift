import Foundation
import OSLog
import Testing

@testable import ShipItKit

/// Integration tests for coverage parsing against pre-recorded fixture files.
///
/// These tests are fully deterministic — no SDK, credentials, or network needed.
/// They verify that `AndroidCoverageParser` and the `shipit coverage` CLI command
/// produce correct output for known input.
///
/// **Prerequisite:** Run `swift build` before running CLI subprocess tests.
@Suite("Coverage Integration")
struct CoverageIntegrationTests {

    // MARK: - AndroidCoverageParser (library-level, no subprocess)

    @Test("AndroidCoverageParser parses fixture and returns known module names")
    func parserReturnsKnownModules() async throws {
        let parser = AndroidCoverageParser(logger: Logger(subsystem: "IntegrationTests", category: "coverage"))
        let modules = try await parser.parse(reportPath: FixturePaths.jacocoReport.path)

        let names = modules.map { $0.name }.sorted()
        #expect(names == ["core", "feature"], "Got: \(names)")
    }

    @Test("AndroidCoverageParser computes correct line coverage for fixture")
    func parserComputesCorrectCoverage() async throws {
        let parser = AndroidCoverageParser(logger: Logger(subsystem: "IntegrationTests", category: "coverage"))
        let modules = try await parser.parse(reportPath: FixturePaths.jacocoReport.path)

        let byName: [String: CoverageTarget] = Dictionary(uniqueKeysWithValues: modules.map { ($0.name, $0) })

        // feature: 80 covered / 100 executable = 80.0%
        let feature = try #require(byName["feature"])
        #expect(feature.coveredLines == 80)
        #expect(feature.executableLines == 100)
        #expect(feature.lineCoverage == 80.0)

        // core: 45 covered / 60 executable = 75.0%
        let core = try #require(byName["core"])
        #expect(core.coveredLines == 45)
        #expect(core.executableLines == 60)
        #expect(core.lineCoverage == 75.0)
    }

    @Test("AndroidCoverageParser lists source files with individual coverage")
    func parserListsSourceFiles() async throws {
        let parser = AndroidCoverageParser(logger: Logger(subsystem: "IntegrationTests", category: "coverage"))
        let modules = try await parser.parse(reportPath: FixturePaths.jacocoReport.path)

        let feature = try #require(modules.first { $0.name == "feature" })
        let fileNames = feature.files.map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted()
        #expect(fileNames.contains("Repository.kt"))
        #expect(fileNames.contains("ViewModel.kt"))
    }

    @Test("AndroidCoverageParser throws on missing report file")
    func parserThrowsOnMissingFile() async throws {
        let parser = AndroidCoverageParser(logger: Logger(subsystem: "IntegrationTests", category: "coverage"))
        await #expect {
            _ = try await parser.parse(reportPath: "/nonexistent/path/jacoco.xml")
        } throws: { error in
            error is ShipItError
        }
    }

    // MARK: - shipit coverage CLI (subprocess)

    @Test("coverage --platform android --report <fixture> exits 0")
    func coverageCLIExitsZero() async throws {
        // Use the ios-sample fixture directory as working directory — it has a Shipfile.yml
        // that lets resolveRequiredConfig succeed; --platform android overrides the platform.
        let result = try await CLI.run(
            "coverage",
            "--platform", "android",
            "--report", FixturePaths.jacocoReport.path,
            workingDirectory: FixturePaths.iosSample
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
    }

    @Test("coverage --platform android --report <fixture> --format json produces valid JSON")
    func coverageCLIProducesValidJSON() async throws {
        let result = try await CLI.run(
            "coverage",
            "--platform", "android",
            "--report", FixturePaths.jacocoReport.path,
            "--format", "json",
            workingDirectory: FixturePaths.iosSample
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")

        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // JSON envelope contains action/status/payload; payload has targets
        #expect(json != nil, "Expected valid JSON output")
    }

    @Test("coverage --platform android --summary prints single line")
    func coverageSummaryPrintsSingleLine() async throws {
        let result = try await CLI.run(
            "coverage",
            "--platform", "android",
            "--report", FixturePaths.jacocoReport.path,
            "--summary",
            workingDirectory: FixturePaths.iosSample
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        let lines = result.stdout.split(separator: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1, "Expected 1 summary line, got \(lines.count): \(result.stdout)")
    }
}

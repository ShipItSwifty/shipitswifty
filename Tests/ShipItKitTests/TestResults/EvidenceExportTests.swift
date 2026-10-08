import Foundation
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Evidence export")
struct EvidenceExportTests {
    private let exporter = EvidenceExporter(shell: .init())

    private func run() -> ParsedTestRun {
        ParsedTestRun(
            runner: .flutterTest, buildSystem: .flutter, source: "events.jsonl", summary: .init(passed: 1),
            testCases: [.init(stableID: "case", name: "test", status: .passed)])
    }

    private func entries(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: Atomic

    @Test(
        "A failed export leaves nothing behind and the same directory can be used again",
        .enabled(if: geteuid() != 0, "file permissions are not enforced for root"))
    func failedExportIsRetryable() async throws {
        let scratch = try TemporaryDirectory()
        let source = scratch.url.appendingPathComponent("source")
        let locked = source.appendingPathComponent("locked.txt")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "readable".write(to: source.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
        try "secret".write(to: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
            try? scratch.remove()
        }
        let exports = scratch.url.appendingPathComponent("exports")
        let destination = exports.appendingPathComponent("run")
        await #expect(throws: (any Error).self) {
            _ = try await exporter.export(runs: [run()], sources: [source.path], to: destination.path)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path), "no half-written export may be visible")
        #expect(entries(in: exports).isEmpty, "the hidden staging directory is removed too")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        let manifest = try await exporter.export(runs: [run()], sources: [source.path], to: destination.path)
        #expect(!manifest.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("index.md").path))
    }

    @Test("A cancelled export leaves nothing behind")
    func cancelledExportLeavesNothing() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let source = scratch.url.appendingPathComponent("log.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let exports = scratch.url.appendingPathComponent("exports")
        let destination = exports.appendingPathComponent("run")
        let exporter = exporter
        let task = Task { try await exporter.export(runs: [], sources: [source.path], to: destination.path) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(entries(in: exports).isEmpty)
    }

    @Test("A successful export leaves only the finished directory")
    func successLeavesNoStaging() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let exports = scratch.url.appendingPathComponent("exports")
        _ = try await exporter.export(runs: [run()], sources: [], to: exports.appendingPathComponent("run").path)
        #expect(entries(in: exports) == ["run"])
    }

    @Test("An export directory that already exists is never touched")
    func existingDestinationIsUntouched() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let destination = scratch.url.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "mine".write(to: destination.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        await #expect(throws: ShipItError.self) { _ = try await exporter.export(runs: [], sources: [], to: destination.path) }
        #expect(entries(in: destination) == ["keep.txt"])
        #expect(entries(in: scratch.url) == ["run"], "no staging directory is left next to it")
    }

    // MARK: Links

    @Test("Links are followed so the export holds real files, cycles end, and dangling links are reported")
    func linksAreFollowed() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let source = scratch.url.appendingPathComponent("source")
        let real = source.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "data".write(to: real.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let fileManager = FileManager.default
        try fileManager.createSymbolicLink(
            at: source.appendingPathComponent("link-file"), withDestinationURL: real.appendingPathComponent("a.txt"))
        try fileManager.createSymbolicLink(at: source.appendingPathComponent("link-dir"), withDestinationURL: real)
        try fileManager.createSymbolicLink(at: real.appendingPathComponent("loop"), withDestinationURL: source)
        try fileManager.createSymbolicLink(
            at: source.appendingPathComponent("ghost"), withDestinationURL: scratch.url.appendingPathComponent("does-not-exist"))
        let destination = scratch.url.appendingPathComponent("export")
        let manifest = try await exporter.export(runs: [], sources: [source.path], to: destination.path)

        let exported = destination.appendingPathComponent("originals/1/source")
        for path in ["link-file", "link-dir", "link-dir/a.txt", "real/a.txt"] {
            let attributes = try fileManager.attributesOfItem(atPath: exported.appendingPathComponent(path).path)
            #expect(attributes[.type] as? FileAttributeType != .typeSymbolicLink, "\(path) must not be a link")
        }
        #expect(try String(contentsOf: exported.appendingPathComponent("link-file"), encoding: .utf8) == "data")
        #expect(manifest.diagnostics.contains { $0.message.contains("does not resolve") })
    }

    @Test("A linked top-level source is exported as its target's content")
    func topLevelLink() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let target = scratch.url.appendingPathComponent("results-123.xml")
        try "<testsuite/>".write(to: target, atomically: true, encoding: .utf8)
        let link = scratch.url.appendingPathComponent("latest.xml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let destination = scratch.url.appendingPathComponent("export")
        _ = try await exporter.export(runs: [], sources: [link.path], to: destination.path)
        let exported = destination.appendingPathComponent("originals/1/latest.xml")
        #expect(try String(contentsOf: exported, encoding: .utf8) == "<testsuite/>")
        let attributes = try FileManager.default.attributesOfItem(atPath: exported.path)
        #expect(attributes[.type] as? FileAttributeType != .typeSymbolicLink)
    }

    // MARK: Versioned, directly readable

    @Test("results.json and coverage.json are versioned, and results.json can be read directly")
    func versionedEnvelopes() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let lcov = scratch.url.appendingPathComponent("lcov.info")
        try "SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n".write(to: lcov, atomically: true, encoding: .utf8)
        let coverage = try await PortableCoverageReader().read(lcov.path, format: .lcov)
        let destination = scratch.url.appendingPathComponent("export")
        _ = try await exporter.export(runs: [run()], sources: [], coverage: [coverage], to: destination.path)

        let results = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("results.json"))) as? [String: Any])
        #expect(results["schemaVersion"] as? Int == 1)
        #expect((results["runs"] as? [Any])?.count == 1)
        let coverageJSON = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("coverage.json"))) as? [String: Any])
        #expect(coverageJSON["schemaVersion"] as? Int == 1)
        #expect((coverageJSON["coverage"] as? [Any])?.count == 1)

        let direct = try await ResultInspection(shell: .init()).read(destination.appendingPathComponent("results.json").path)
        #expect(direct.testCases.first?.name == "test")
        let byDirectory = try await ResultInspection(shell: .init()).read(destination.path)
        #expect(byDirectory.summary.passed == 1)
    }

    // MARK: Index

    @Test("The index summarizes each coverage report separately and says they are not summed")
    func indexCoverageSummary() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let first = scratch.url.appendingPathComponent("unit.info")
        let second = scratch.url.appendingPathComponent("ui.info")
        try "SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n".write(to: first, atomically: true, encoding: .utf8)
        try "SF:lib/a.dart\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nend_of_record\n".write(to: second, atomically: true, encoding: .utf8)
        let reports = [
            try await PortableCoverageReader().read(first.path, format: .lcov),
            try await PortableCoverageReader().read(second.path, format: .lcov),
        ]
        let destination = scratch.url.appendingPathComponent("export")
        _ = try await exporter.export(runs: [], sources: [], coverage: reports, to: destination.path)
        let index = try String(contentsOf: destination.appendingPathComponent("index.md"), encoding: .utf8)
        #expect(index.contains("## Coverage"))
        #expect(index.contains("unit.info (unknown): 50.0%, 1 of 2 lines"))
        #expect(index.contains("ui.info (unknown): 75.0%, 3 of 4 lines"))
        #expect(index.contains("never summed"))
    }

    @Test("An export without coverage has no coverage section")
    func indexWithoutCoverage() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let destination = scratch.url.appendingPathComponent("export")
        _ = try await exporter.export(runs: [run()], sources: [], to: destination.path)
        #expect(!(try String(contentsOf: destination.appendingPathComponent("index.md"), encoding: .utf8)).contains("## Coverage"))
    }
}

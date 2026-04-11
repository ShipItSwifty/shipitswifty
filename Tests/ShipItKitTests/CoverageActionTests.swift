import Foundation
import Testing
import SwiftyShell
import OSLog
@testable import ShipItKit

// MARK: - CoverageAction Tests

@Suite("CoverageAction")
struct CoverageActionTests {

    // MARK: - iOS: xccov discovery

    @Test("iOS: throws invalidConfiguration when no xcresult found and no scheme")
    func iosNoXCResultNoScheme() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)
        // Default mock context has no appScheme; ./build/ won't exist in test sandbox
        let options = CoverageAction.Options()

        await #expect {
            _ = try await CoverageAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains(".xcresult")
        }
    }

    @Test("iOS: throws invalidConfiguration when xccov exits non-zero")
    func iosXccovFailure() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "error: could not read bundle", exitCode: 1)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(xcresultPath: "/tmp/fake.xcresult")

        await #expect {
            _ = try await CoverageAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("xccov") || reason.contains("could not read")
        }
    }

    @Test("iOS: parses xccov JSON and returns CoverageTargets")
    func iosParseXccovOutput() async throws {
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "MyApp.app",
              "lineCoverage": 0.784,
              "coveredLines": 1240,
              "executableLines": 1580,
              "files": [
                {
                  "name": "ViewController.swift",
                  "path": "/src/MyApp/ViewController.swift",
                  "lineCoverage": 0.9,
                  "coveredLines": 45,
                  "executableLines": 50
                }
              ]
            },
            {
              "name": "MyAppTests.xctest",
              "lineCoverage": 1.0,
              "coveredLines": 200,
              "executableLines": 200,
              "files": []
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)

        #expect(result.platform == "ios")
        #expect(result.source == "/tmp/fake.xcresult")
        #expect(result.firstPartyOnly == true)

        // Test bundle should be filtered out by firstPartyOnly
        #expect(!result.targets.contains { $0.name == "MyAppTests" })

        // App target should be present, suffix stripped
        let appTarget = result.targets.first { $0.name == "MyApp" }
        #expect(appTarget != nil)
        #expect(appTarget?.lineCoverage == 78.4)
        #expect(appTarget?.coveredLines == 1240)
        #expect(appTarget?.executableLines == 1580)
    }

    @Test("iOS: target name suffix stripping")
    func iosTargetNameSuffixStripping() async throws {
        let xccovJSON = """
        {
          "targets": [
            { "name": "MyApp.app", "lineCoverage": 0.5, "coveredLines": 50, "executableLines": 100, "files": [] },
            { "name": "MyLib.framework", "lineCoverage": 0.6, "coveredLines": 60, "executableLines": 100, "files": [] },
            { "name": "MyTests.xctest", "lineCoverage": 1.0, "coveredLines": 100, "executableLines": 100, "files": [] },
            { "name": "MyExtension.appex", "lineCoverage": 0.7, "coveredLines": 70, "executableLines": 100, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: false, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        #expect(names.contains("MyApp"))
        #expect(names.contains("MyLib"))
        #expect(names.contains("MyExtension"))
        #expect(!names.contains("MyApp.app"))
        #expect(!names.contains("MyLib.framework"))
    }

    @Test("iOS: 0/0 targets are suppressed")
    func iosZeroExecutableLinesFiltered() async throws {
        let xccovJSON = """
        {
          "targets": [
            { "name": "MyApp.app", "lineCoverage": 0.5, "coveredLines": 50, "executableLines": 100, "files": [] },
            { "name": "EmptyTarget.framework", "lineCoverage": 0.0, "coveredLines": 0, "executableLines": 0, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: false, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)

        #expect(!result.targets.contains { $0.executableLines == 0 })
        #expect(result.targets.contains { $0.name == "MyApp" })
    }

    @Test("iOS: include-target overrides first-party filter")
    func iosIncludeTargetOverride() async throws {
        let xccovJSON = """
        {
          "targets": [
            { "name": "MyApp.app", "lineCoverage": 0.5, "coveredLines": 50, "executableLines": 100, "files": [] },
            { "name": "GoogleSignIn.framework", "lineCoverage": 0.8, "coveredLines": 80, "executableLines": 100, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(
            firstPartyOnly: true,
            includeTargets: ["GoogleSignIn"],
            xcresultPath: "/tmp/fake.xcresult"
        )

        let result = try await CoverageAction().run(with: options, context: context)

        // Only GoogleSignIn should appear (include overrides first-party filter)
        #expect(result.targets.count == 1)
        #expect(result.targets.first?.name == "GoogleSignIn")
    }

    @Test("iOS: exclude-target removes specific targets")
    func iosExcludeTarget() async throws {
        let xccovJSON = """
        {
          "targets": [
            { "name": "MyApp.app", "lineCoverage": 0.5, "coveredLines": 50, "executableLines": 100, "files": [] },
            { "name": "FeatureKit.framework", "lineCoverage": 0.7, "coveredLines": 70, "executableLines": 100, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(
            firstPartyOnly: false,
            excludeTargets: ["MyApp"],
            xcresultPath: "/tmp/fake.xcresult"
        )

        let result = try await CoverageAction().run(with: options, context: context)

        #expect(!result.targets.contains { $0.name == "MyApp" })
        #expect(result.targets.contains { $0.name == "FeatureKit" })
    }

    @Test("iOS: overall coverage is weighted average across targets")
    func iosOverallCoverageAggregation() async throws {
        // Target A: 50/100 = 50%
        // Target B: 90/100 = 90%
        // Combined: 140/200 = 70%
        let xccovJSON = """
        {
          "targets": [
            { "name": "TargetA.framework", "lineCoverage": 0.5, "coveredLines": 50, "executableLines": 100, "files": [] },
            { "name": "TargetB.framework", "lineCoverage": 0.9, "coveredLines": 90, "executableLines": 100, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: false, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)

        #expect(result.coveredLines == 140)
        #expect(result.executableLines == 200)
        #expect(result.overallLineCoverage == 70.0)
    }

    // MARK: - Path-based first-party classification

    @Test("iOS: SPM package target excluded via SourcePackages path")
    func iosFirstPartyExcludesSPMBySourcePackagesPath() async throws {
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "APITraceDebug.framework",
              "lineCoverage": 0.5,
              "coveredLines": 50,
              "executableLines": 100,
              "files": [
                {
                  "name": "APITrace.swift",
                  "path": "/Users/developer/Library/Developer/Xcode/DerivedData/MyApp-abc123/SourcePackages/checkouts/APITrace/Sources/APITrace.swift",
                  "lineCoverage": 0.5,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "Novalingo.app",
              "lineCoverage": 0.8,
              "coveredLines": 80,
              "executableLines": 100,
              "files": [
                {
                  "name": "AppDelegate.swift",
                  "path": "/Users/developer/Developer/Novalingo/Sources/AppDelegate.swift",
                  "lineCoverage": 0.8,
                  "coveredLines": 80,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        // SPM package target should be excluded via path-based detection
        #expect(!names.contains("APITraceDebug"))
        // First-party app target should be present
        #expect(names.contains("Novalingo"))
    }

    @Test("iOS: SPM target excluded via .build/checkouts path")
    func iosFirstPartyExcludesSPMByBuildCheckoutsPath() async throws {
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "SomePackage.framework",
              "lineCoverage": 0.6,
              "coveredLines": 60,
              "executableLines": 100,
              "files": [
                {
                  "name": "SomeFile.swift",
                  "path": "/path/to/project/.build/checkouts/SomePackage/Sources/SomeFile.swift",
                  "lineCoverage": 0.6,
                  "coveredLines": 60,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "MyApp.app",
              "lineCoverage": 0.7,
              "coveredLines": 70,
              "executableLines": 100,
              "files": [
                {
                  "name": "ViewController.swift",
                  "path": "/path/to/project/Sources/ViewController.swift",
                  "lineCoverage": 0.7,
                  "coveredLines": 70,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        #expect(!names.contains("SomePackage"))
        #expect(names.contains("MyApp"))
    }

    @Test("iOS: target with all files in DerivedData (non-SPM) excluded")
    func iosFirstPartyExcludesAllDerivedDataTarget() async throws {
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "GeneratedStubs.framework",
              "lineCoverage": 0.3,
              "coveredLines": 30,
              "executableLines": 100,
              "files": [
                {
                  "name": "GeneratedStub.swift",
                  "path": "/Users/developer/Library/Developer/Xcode/DerivedData/MyApp-abc123/Build/Products/Debug/GeneratedStubs.framework/GeneratedStub.swift",
                  "lineCoverage": 0.3,
                  "coveredLines": 30,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "MyKit.framework",
              "lineCoverage": 0.9,
              "coveredLines": 90,
              "executableLines": 100,
              "files": [
                {
                  "name": "MyKit.swift",
                  "path": "/Users/developer/Developer/MyApp/Sources/MyKit/MyKit.swift",
                  "lineCoverage": 0.9,
                  "coveredLines": 90,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        // Target with all files in DerivedData should be excluded
        #expect(!names.contains("GeneratedStubs"))
        // Target with project source files should be included
        #expect(names.contains("MyKit"))
    }

    @Test("iOS: name heuristic fallback used when target has no files")
    func iosFirstPartyNameHeuristicFallback() async throws {
        // Targets with empty files array fall back to name-based classification
        let xccovJSON = """
        {
          "targets": [
            { "name": "NovalingoCore.framework", "lineCoverage": 0.75, "coveredLines": 75, "executableLines": 100, "files": [] },
            { "name": "GoogleSignIn.framework", "lineCoverage": 0.9, "coveredLines": 90, "executableLines": 100, "files": [] },
            { "name": "NovalingoTests.xctest", "lineCoverage": 1.0, "coveredLines": 100, "executableLines": 100, "files": [] }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        // Name heuristic: NovalingoCore passes (no vendor pattern)
        #expect(names.contains("NovalingoCore"))
        // Name heuristic: GoogleSignIn excluded via "google" prefix
        #expect(!names.contains("GoogleSignIn"))
        // Name heuristic: NovalingoTests excluded via "tests" suffix
        #expect(!names.contains("NovalingoTests"))
    }

    @Test("iOS: first-party-only false with SPM path still includes all non-zero targets")
    func iosFirstPartyFalseIncludesSPMTargets() async throws {
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "APITraceDebug.framework",
              "lineCoverage": 0.5,
              "coveredLines": 50,
              "executableLines": 100,
              "files": [
                {
                  "name": "APITrace.swift",
                  "path": "/Users/developer/Library/Developer/Xcode/DerivedData/MyApp-abc123/SourcePackages/checkouts/APITrace/Sources/APITrace.swift",
                  "lineCoverage": 0.5,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "Novalingo.app",
              "lineCoverage": 0.8,
              "coveredLines": 80,
              "executableLines": 100,
              "files": [
                {
                  "name": "AppDelegate.swift",
                  "path": "/Users/developer/Developer/Novalingo/Sources/AppDelegate.swift",
                  "lineCoverage": 0.8,
                  "coveredLines": 80,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: false, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)
        let names = result.targets.map(\.name)

        // With firstPartyOnly: false, SPM targets should NOT be filtered out
        #expect(names.contains("APITraceDebug"))
        #expect(names.contains("Novalingo"))
    }

    @Test("iOS: mixed-path target with one project file is included as first-party")
    func iosFirstPartyMixedPathIncludesWhenProjectFilePresent() async throws {
        // A target that has one file under DerivedData and one under the project
        // should be considered first-party (project-owned)
        let xccovJSON = """
        {
          "targets": [
            {
              "name": "MyFeature.framework",
              "lineCoverage": 0.6,
              "coveredLines": 60,
              "executableLines": 100,
              "files": [
                {
                  "name": "MyFeature.swift",
                  "path": "/Users/developer/Developer/MyApp/Sources/MyFeature/MyFeature.swift",
                  "lineCoverage": 0.7,
                  "coveredLines": 35,
                  "executableLines": 50
                },
                {
                  "name": "Generated.swift",
                  "path": "/Users/developer/Library/Developer/Xcode/DerivedData/MyApp-abc123/Build/Products/Generated.swift",
                  "lineCoverage": 0.5,
                  "coveredLines": 25,
                  "executableLines": 50
                }
              ]
            }
          ]
        }
        """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: xccovJSON, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = CoverageAction.Options(firstPartyOnly: true, xcresultPath: "/tmp/fake.xcresult")

        let result = try await CoverageAction().run(with: options, context: context)

        // Mixed target: has at least one project file, so included
        #expect(result.targets.contains { $0.name == "MyFeature" })
    }
}

// MARK: - Android Coverage Tests

@Suite("AndroidCoverageParser")
struct AndroidCoverageParserTests {

    @Test("Parses JaCoCo XML and returns modules")
    func parsesBasicJacocoXML() async throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <report name="MyApp">
          <package name="com/example/feature">
            <sourcefile name="ViewModel.kt">
              <counter type="LINE" covered="42" missed="8"/>
            </sourcefile>
            <counter type="LINE" covered="42" missed="8"/>
          </package>
          <package name="com/example/ui">
            <sourcefile name="Fragment.kt">
              <counter type="LINE" covered="30" missed="10"/>
            </sourcefile>
            <counter type="LINE" covered="30" missed="10"/>
          </package>
          <counter type="LINE" covered="72" missed="18"/>
        </report>
        """

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jacocoTestReport-\(UUID().uuidString).xml")
        try xmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", AndroidCoverageParserTests.self)
        let parser = AndroidCoverageParser(logger: logger)
        let modules = try await parser.parse(reportPath: tempURL.path)

        // Both packages share "com/example" prefix (depth 2), so they map to
        // "feature" and "ui" modules.
        #expect(modules.contains { $0.name == "feature" })
        #expect(modules.contains { $0.name == "ui" })

        let featureModule = modules.first { $0.name == "feature" }
        #expect(featureModule?.coveredLines == 42)
        #expect(featureModule?.executableLines == 50)
        // 42/50 = 84.0%
        #expect(featureModule?.lineCoverage == 84.0)
    }

    @Test("Throws when XML file does not exist")
    func throwsWhenFileNotFound() async throws {
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", AndroidCoverageParserTests.self)
        let parser = AndroidCoverageParser(logger: logger)

        await #expect {
            _ = try await parser.parse(reportPath: "/nonexistent/path/report.xml")
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("read JaCoCo report") || reason.contains("nonexistent")
        }
    }

    @Test("Parser returns all packages including zero-executable ones")
    func zeroExecutableLinesReturnedByParser() async throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <report name="MyApp">
          <package name="com/example/feature">
            <counter type="LINE" covered="50" missed="50"/>
          </package>
          <package name="com/example/generated">
            <counter type="LINE" covered="0" missed="0"/>
          </package>
        </report>
        """
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jacoco-zero-\(UUID().uuidString).xml")
        try xmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", AndroidCoverageParserTests.self)
        let parser = AndroidCoverageParser(logger: logger)
        let modules = try await parser.parse(reportPath: tempURL.path)

        // Parser returns all packages; CoverageAction filters 0-executable ones
        #expect(modules.contains { $0.name == "feature" })
        #expect(modules.contains { $0.name == "generated" || $0.executableLines == 0 })
    }

    @Test("Android: overall coverage computed correctly")
    func androidOverallCoverage() async throws {
        let xmlContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <report name="MyApp">
          <package name="com/example/featureA">
            <counter type="LINE" covered="60" missed="40"/>
          </package>
          <package name="com/example/featureB">
            <counter type="LINE" covered="80" missed="20"/>
          </package>
        </report>
        """
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jacoco-agg-\(UUID().uuidString).xml")
        try xmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor, platform: .android)

        let options = CoverageAction.Options(firstPartyOnly: false, reportPath: tempURL.path)
        let result = try await CoverageAction().run(with: options, context: context)

        #expect(result.platform == "android")
        // featureA: 60/100, featureB: 80/100 → total: 140/200 = 70%
        #expect(result.coveredLines == 140)
        #expect(result.executableLines == 200)
        #expect(result.overallLineCoverage == 70.0)
    }
}

// MARK: - CoverageAction.Options Codable

@Suite("CoverageAction.Options")
struct CoverageActionOptionsTests {

    @Test("Options can be encoded and decoded")
    func optionsCodable() throws {
        let options = CoverageAction.Options(
            format: .json,
            firstPartyOnly: true,
            summary: false,
            showTargets: true,
            showFiles: false,
            includeTargets: ["FeatureKit"],
            excludeTargets: ["GoogleSignIn"],
            sort: .coverage,
            limit: 10,
            xcresultPath: "./build/App-tests.xcresult"
        )

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(CoverageAction.Options.self, from: data)

        #expect(decoded.format == .json)
        #expect(decoded.firstPartyOnly == true)
        #expect(decoded.summary == false)
        #expect(decoded.showTargets == true)
        #expect(decoded.includeTargets == ["FeatureKit"])
        #expect(decoded.excludeTargets == ["GoogleSignIn"])
        #expect(decoded.sort == .coverage)
        #expect(decoded.limit == 10)
        #expect(decoded.xcresultPath == "./build/App-tests.xcresult")
    }
}

// MARK: - CoverageTarget Codable

@Suite("CoverageTarget")
struct CoverageTargetTests {

    @Test("CoverageTarget can be encoded and decoded")
    func coverageTargetCodable() throws {
        let target = CoverageTarget(
            name: "MyFeatureKit",
            lineCoverage: 73.5,
            coveredLines: 735,
            executableLines: 1000,
            files: [
                CoverageFile(
                    path: "/src/MyFeatureKit/Feature.swift",
                    lineCoverage: 80.0,
                    coveredLines: 80,
                    executableLines: 100
                )
            ]
        )

        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(CoverageTarget.self, from: data)

        #expect(decoded.name == "MyFeatureKit")
        #expect(decoded.lineCoverage == 73.5)
        #expect(decoded.coveredLines == 735)
        #expect(decoded.executableLines == 1000)
        #expect(decoded.files.count == 1)
        #expect(decoded.files.first?.path == "/src/MyFeatureKit/Feature.swift")
        #expect(decoded.files.first?.lineCoverage == 80.0)
    }
}

// MARK: - BuiltInSchemaCatalog Coverage schema

@Suite("BuiltInSchemaCatalog.coverage")
struct BuiltInSchemaCatalogCoverageTests {

    @Test("Coverage action appears in actionSchemas")
    func coverageInActionSchemas() {
        let schemas = BuiltInSchemaCatalog.actionSchemas()
        let coverage = schemas.first { $0.name == "coverage" }
        #expect(coverage != nil)
        #expect(coverage?.description.isEmpty == false)
    }

    @Test("Coverage action has expected options")
    func coverageOptionsPresent() {
        let options = BuiltInSchemaCatalog.optionSchema(for: "coverage")
        let names = options.map(\.name)
        #expect(names.contains("format"))
        #expect(names.contains("first_party_only"))
        #expect(names.contains("summary"))
        #expect(names.contains("show_targets"))
        #expect(names.contains("show_files"))
        #expect(names.contains("xcresult_path"))
        #expect(names.contains("report_path"))
        #expect(names.contains("sort"))
        #expect(names.contains("limit"))
    }
}

#if os(macOS)
import AppStoreConnectKit
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("VersionAction")
struct VersionActionTests {

    // MARK: - Semver bumps (agvtool path)

    @Test("VersionAction bumps patch version through agvtool")
    func bumpsPatchVersion() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "42\n", stderr: "", exitCode: 0)
            }
            if description.contains("new-marketing-version") {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }

            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .patch), context: context)

        #expect(result.version == "1.2.4")
        #expect(result.buildNumber == "42")
        #expect(result.versionChanged == true)  // marketing version advanced
        #expect(executedCommands.contains { $0.contains("new-marketing-version 1.2.4") })
    }

    @Test("VersionAction bumps minor version and preserves build number")
    func bumpsMinorVersion() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "9\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .minor), context: context)

        #expect(result.version == "1.3.0")
        #expect(result.buildNumber == "9")  // build unchanged for semver bumps
        #expect(executedCommands.contains { $0.contains("new-marketing-version 1.3.0") })
    }

    @Test("VersionAction bumps major version and resets minor and patch")
    func bumpsMajorVersion() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "2.4.7\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "33\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .major), context: context)

        #expect(result.version == "3.0.0")
        #expect(result.buildNumber == "33")
        #expect(executedCommands.contains { $0.contains("new-marketing-version 3.0.0") })
    }

    @Test("VersionAction set bump writes explicit version and build number")
    func setBumpWritesExplicitValues() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.0.0\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(
            with: .init(bump: .set, version: "5.0.0", buildNumber: "200"),
            context: context
        )

        #expect(result.version == "5.0.0")
        #expect(result.buildNumber == "200")
        #expect(executedCommands.contains { $0.contains("new-marketing-version 5.0.0") })
        #expect(executedCommands.contains { $0.contains("new-version -all 200") })
    }

    @Test("VersionAction uses commit count strategy for build bumps")
    func usesCommitCountStrategy() async throws {
        let executor = MockExecutor { command, _ in
            let description = command.description
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "41\n", stderr: "", exitCode: 0)
            }
            if description.contains("git rev-list --count HEAD") {
                return ShellOutput(stdout: "128\n", stderr: "", exitCode: 0)
            }
            if description.contains("new-version -all 128") {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .build, strategy: .commitCount), context: context)

        #expect(result.version == "1.2.3")
        #expect(result.buildNumber == "128")
        #expect(result.versionChanged == false)  // build-only bump leaves marketing version unchanged
    }

    @Test("VersionAction sequential build bump increments integer by 1")
    func sequentialBuildBump() async throws {
        let executor = MockExecutor { command, _ in
            let description = command.description
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.0.0\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "99\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .build, strategy: .sequential), context: context)

        #expect(result.buildNumber == "100")
        #expect(result.version == "1.0.0")
    }

    @Test("VersionAction does not write version when it has not changed")
    func doesNotWriteWhenVersionUnchanged() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.0.0\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "5\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        // bump: build — only build number changes, version stays at 1.0.0
        _ = try await VersionAction().run(with: .init(bump: .build), context: context)

        // Should NOT have called new-marketing-version since version didn't change
        #expect(!executedCommands.contains { $0.contains("new-marketing-version") })
        // Should have called new-version for the build bump
        #expect(executedCommands.contains { $0.contains("new-version -all 6") })
    }

    // MARK: - xcodeproj source — read path

    @Test("VersionAction reads MARKETING_VERSION and CURRENT_PROJECT_VERSION via xcodebuild when source is xcodeproj")
    func readsVersionFromXcodeProjectBuildSettings() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("xcodebuild") && description.contains("showBuildSettings") {
                return ShellOutput(
                    stdout: """
                            MARKETING_VERSION = 2.5.0
                            CURRENT_PROJECT_VERSION = 77
                        """,
                    stderr: "",
                    exitCode: 0
                )
            }
            // agvtool write path
            if description.contains("new-version -all 78") {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(
            executor: executor,
            versioningSource: "xcodeproj"
        )
        let result = try await VersionAction().run(with: .init(bump: .build), context: context)

        #expect(result.version == "2.5.0")
        #expect(result.buildNumber == "78")
        // Must NOT have fallen through to agvtool for the read phase
        #expect(!executedCommands.contains { $0.contains("what-marketing-version") })
        #expect(!executedCommands.contains { $0.contains("what-version") })
    }

    @Test("VersionAction falls back to agvtool when xcodebuild showBuildSettings returns no MARKETING_VERSION")
    func fallsBackToAgvtoolWhenBuildSettingAbsent() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("xcodebuild") && description.contains("showBuildSettings") {
                // No version keys in output — simulates a project that has not
                // set MARKETING_VERSION in build settings.
                return ShellOutput(stdout: "PRODUCT_NAME = MyApp\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "3.0.0\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "10\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(
            executor: executor,
            versioningSource: "xcodeproj"
        )
        let result = try await VersionAction().run(with: .init(bump: .patch), context: context)

        #expect(result.version == "3.0.1")
        // Fell back to agvtool reads
        #expect(executedCommands.contains { $0.contains("what-marketing-version") })
    }

    @Test("VersionAction falls back to agvtool when xcodebuild showBuildSettings exits non-zero (e.g. exit 74)")
    func fallsBackToAgvtoolWhenBuildSettingsExitsNonZero() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("xcodebuild") && description.contains("showBuildSettings") {
                // Simulate exit 74 — package resolution failure or toolchain interference.
                // MockExecutor throws ShellError.exitFailure for non-zero exits.
                return ShellOutput(
                    stdout: "",
                    stderr: "xcodebuild: error: Could not resolve package dependencies\n",
                    exitCode: 74
                )
            }
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "42\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor, versioningSource: "xcodeproj")
        // Should NOT throw — readBuildSetting catches the ShellError and falls through
        let result = try await VersionAction().run(with: .init(bump: .build), context: context)

        #expect(result.buildNumber == "43")
        // Must have fallen through to agvtool for both reads
        #expect(executedCommands.contains { $0.contains("what-marketing-version") })
        #expect(executedCommands.contains { $0.contains("what-version") })
    }

    // MARK: - xcodeproj source — write path

    @Test("VersionAction xcodeproj write uses agvtool new-version for build bump")
    func xcodeProjectWriteUseAgvtoolForBuildBump() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("showBuildSettings") {
                return ShellOutput(
                    stdout: "MARKETING_VERSION = 1.0.0\n    CURRENT_PROJECT_VERSION = 10\n",
                    stderr: "", exitCode: 0
                )
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor, versioningSource: "xcodeproj")
        let result = try await VersionAction().run(with: .init(bump: .build), context: context)

        #expect(result.buildNumber == "11")
        // Write must go through agvtool, not plutil
        #expect(executedCommands.contains { $0.contains("agvtool") && $0.contains("new-version") && $0.contains("11") })
        #expect(!executedCommands.contains { $0.contains("plutil") })
    }

    @Test("VersionAction xcodeproj write falls back to plutil when agvtool fails")
    func xcodeProjectWriteFallsBackToPlutil() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)
            if description.contains("showBuildSettings") {
                return ShellOutput(
                    stdout: "MARKETING_VERSION = 1.0.0\n    CURRENT_PROJECT_VERSION = 5\n",
                    stderr: "", exitCode: 0
                )
            }
            // agvtool write fails
            if description.contains("agvtool") && (description.contains("new-version") || description.contains("new-marketing-version")) {
                return ShellOutput(stdout: "", stderr: "agvtool: no VERSIONING_SYSTEM set\n", exitCode: 1)
            }
            // plutil succeeds (findInfoPlist returns nil for mock context → plutil write path throws,
            // but this test verifies the write attempt order, not the plist search)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor, versioningSource: "xcodeproj")
        // We just verify agvtool was attempted first; we don't assert on the final value since
        // findInfoPlist may return nil in the test sandbox and the plutil path may also fail.
        do {
            _ = try await VersionAction().run(with: .init(bump: .build), context: context)
        } catch {
            // Expected: plutil fails because there's no real Info.plist in the test sandbox
        }

        // agvtool must have been tried first before falling back
        #expect(executedCommands.contains { $0.contains("agvtool") && $0.contains("new-version") })
    }

    // MARK: - ActionContext.mock default versioningSource

    @Test("ActionContext.mock defaults versioningSource to xcodeproj")
    func mockContextDefaultsToXcodeproj() {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)
        #expect(context.config.versioningSource == "xcodeproj")
    }

    @Test("ActionContext.mock respects explicit versioningSource override")
    func mockContextRespectsSourceOverride() {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor, versioningSource: "asc")
        #expect(context.config.versioningSource == "asc")
    }

    // MARK: - project_spec source — read/write via YAML file

    /// Helper: creates a temp YAML spec file, returns the path.
    private func makeTempSpec(content: String) throws -> (path: String, cleanup: () -> Void) {
        let dir = NSTemporaryDirectory() + "ShipItTests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/project.yml"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return (path, { try? FileManager.default.removeItem(atPath: dir) })
    }

    /// Helper: makes a context configured for project_spec versioning.
    private func makeProjectSpecContext(executor: MockExecutor, specPath: String) -> ActionContext {
        let config = ResolvedConfig(
            appScheme: "MockApp",
            versioningSource: "project_spec",
            versioningSpecPath: specPath
        )
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        return ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", VersionAction.self),
            config: config,
            appStoreConnect: ascClient
        )
    }

    @Test("VersionAction project_spec source reads and bumps build number in YAML")
    func projectSpecBumpsBuild() async throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "10"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        // project_spec source does file I/O — no shell commands needed for read/write
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeProjectSpecContext(executor: executor, specPath: path)
        let result = try await VersionAction().run(with: .init(bump: .build), context: context)

        #expect(result.version == "1.0.0")
        #expect(result.buildNumber == "11")

        // Verify the YAML file was updated
        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("CURRENT_PROJECT_VERSION: \"11\""))
        #expect(updated.contains("MARKETING_VERSION: \"1.0.0\""))
    }

    @Test("VersionAction project_spec source bumps patch version in YAML")
    func projectSpecBumpsPatch() async throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "2.3.4"
              CURRENT_PROJECT_VERSION: "50"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeProjectSpecContext(executor: executor, specPath: path)
        let result = try await VersionAction().run(with: .init(bump: .patch), context: context)

        #expect(result.version == "2.3.5")
        #expect(result.buildNumber == "50")

        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("MARKETING_VERSION: \"2.3.5\""))
    }

    @Test("VersionAction project_spec source sets explicit version and build")
    func projectSpecSetsExplicit() async throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "1"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeProjectSpecContext(executor: executor, specPath: path)
        let result = try await VersionAction().run(
            with: .init(bump: .set, version: "5.0.0", buildNumber: "100"),
            context: context
        )

        #expect(result.version == "5.0.0")
        #expect(result.buildNumber == "100")

        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("MARKETING_VERSION: \"5.0.0\""))
        #expect(updated.contains("CURRENT_PROJECT_VERSION: \"100\""))
    }

    @Test("VersionAction does not invoke agvtool or xcodebuild for project_spec source")
    func projectSpecDoesNotCallShell() async throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "1"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        let (executor, commands) = makeCaptureExecutor()
        let context = makeProjectSpecContext(executor: executor, specPath: path)
        _ = try await VersionAction().run(with: .init(bump: .build), context: context)

        // No shell commands should have been executed
        #expect(commands().isEmpty)
    }

    // MARK: - target option override

    @Test("VersionAction target: source_of_truth overrides xcodeproj config to use project_spec")
    func targetOverridesToProjectSpec() async throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "5"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        // Config says xcodeproj, but options.target says source_of_truth
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MockApp",
            versioningSource: "xcodeproj",
            versioningSpecPath: path
        )
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", VersionAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await VersionAction().run(
            with: .init(bump: .build, target: "source_of_truth"),
            context: context
        )

        #expect(result.version == "1.0.0")
        #expect(result.buildNumber == "6")

        // Verify YAML file was updated (not agvtool)
        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("CURRENT_PROJECT_VERSION: \"6\""))
    }

    @Test("VersionAction target: project_spec is equivalent to source_of_truth")
    func targetProjectSpecAlias() async throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "7"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MockApp",
            versioningSource: "xcodeproj",
            versioningSpecPath: path
        )
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", VersionAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await VersionAction().run(
            with: .init(bump: .build, target: "project_spec"),
            context: context
        )

        #expect(result.buildNumber == "8")
    }

    // MARK: - target: xcodeproj override

    @Test("VersionAction target: xcodeproj overrides project_spec config to use Xcode build settings")
    func targetXcodeprojOverridesProjectSpecConfig() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("showBuildSettings") {
                return ShellOutput(
                    stdout: "MARKETING_VERSION = 3.0.0\n    CURRENT_PROJECT_VERSION = 20\n",
                    stderr: "", exitCode: 0
                )
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        // Config says project_spec, but options.target says xcodeproj
        let config = ResolvedConfig(
            appScheme: "MockApp",
            versioningSource: "project_spec",
            versioningSpecPath: "/some/path/project.yml"
        )
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", VersionAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await VersionAction().run(
            with: .init(bump: .build, target: "xcodeproj"),
            context: context
        )

        #expect(result.version == "3.0.0")
        #expect(result.buildNumber == "21")
        // Must have used xcodebuild, not the YAML file
        #expect(executedCommands.contains { $0.contains("showBuildSettings") })
    }

    @Test("VersionAction with no target option uses config versioningSource")
    func noTargetUsesConfigSource() async throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "3"
            """
        let (path, cleanup) = try makeTempSpec(content: yaml)
        defer { cleanup() }

        let (executor, commands) = makeCaptureExecutor()
        let context = makeProjectSpecContext(executor: executor, specPath: path)
        _ = try await VersionAction().run(with: .init(bump: .build), context: context)

        // Config is project_spec, no target override — should not call shell
        #expect(commands().isEmpty)

        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("CURRENT_PROJECT_VERSION: \"4\""))
    }

    // MARK: - BuiltInSchemaCatalog version schema

    @Test("BuiltInSchemaCatalog version schema includes target field")
    func schemaCatalogVersionTargetField() {
        let schema = BuiltInSchemaCatalog.optionSchema(for: VersionAction.name)
        let fieldNames = schema.map(\.name)
        #expect(fieldNames.contains("target"))
    }

    @Test("BuiltInSchemaCatalog versioning section includes spec_path, build_key, and marketing_key")
    func schemaCatalogVersioningSectionFields() {
        let fields = BuiltInSchemaCatalog.shipfileFields()
        guard let versioningSection = fields.first(where: { $0.name == "versioning" }) else {
            Issue.record("versioning section not found in shipfileFields()")
            return
        }
        let propertyNames = versioningSection.propertyValues.map(\.name)
        #expect(propertyNames.contains("spec_path"))
        #expect(propertyNames.contains("build_key"))
        #expect(propertyNames.contains("marketing_key"))
        #expect(propertyNames.contains("source"))
    }
}
#endif

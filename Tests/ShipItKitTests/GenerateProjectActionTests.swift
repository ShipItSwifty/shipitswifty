import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

@Suite("GenerateProjectAction")
struct GenerateProjectActionTests {

    // MARK: - Success cases

    @Test("runs the configured generation command and returns result")
    func runsGenerationCommand() async throws {
        let (executor, commands) = makeCaptureExecutor { command, _ in
            ShellOutput(stdout: "Generated project\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationSpecPath: nil,
            projectGenerationOutputProject: nil,
            projectGenerationAutoGenerate: true
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await GenerateProjectAction().run(with: .init(force: true), context: context)

        #expect(result.generated == true)
        #expect(result.commandExecuted == "xcodegen generate")
        #expect(commands().contains { $0.contains("xcodegen") && $0.contains("generate") })
    }

    @Test("throws invalidConfiguration when no command is configured")
    func throwsWhenNoCommandConfigured() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: nil,
            projectGenerationCommand: nil
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        await #expect(throws: ShipItError.self) {
            _ = try await GenerateProjectAction().run(with: .init(), context: context)
        }
    }

    @Test("throws buildFailed when generation command exits non-zero")
    func throwsWhenCommandFails() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "Error: spec parse failed\n", exitCode: 1)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate"
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        await #expect(throws: ShipItError.self) {
            _ = try await GenerateProjectAction().run(with: .init(force: true), context: context)
        }
    }

    @Test("uses option command override over config")
    func usesOptionCommandOverride() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate"
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await GenerateProjectAction().run(
            with: .init(command: "xcodegen generate --spec alt.yml", force: true),
            context: context
        )

        #expect(result.commandExecuted == "xcodegen generate --spec alt.yml")
        #expect(commands().contains { $0.contains("alt.yml") })
    }

    // MARK: - Spec path validation

    @Test("throws invalidConfiguration when specPath points to a nonexistent file")
    func throwsWhenSpecPathNotFound() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationSpecPath: "/nonexistent/path/project.yml"
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        await #expect(throws: ShipItError.self) {
            _ = try await GenerateProjectAction().run(with: .init(force: true), context: context)
        }
    }

    @Test("option specPath overrides config specPath and validates the option path")
    func optionSpecPathOverridesConfig() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationSpecPath: nil  // no config path
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        // Option specPath to a nonexistent file should throw
        await #expect(throws: ShipItError.self) {
            _ = try await GenerateProjectAction().run(
                with: .init(specPath: "/nonexistent/option/spec.yml", force: true),
                context: context
            )
        }
    }

    // MARK: - Skip when output exists

    @Test("skips generation when force is false and output project already exists")
    func skipsWhenOutputProjectExists() async throws {
        // Create a temp directory to act as the "output project"
        let dir = NSTemporaryDirectory() + "ShipItTests-\(UUID().uuidString)"
        let outputProject = dir + "/MockApp.xcodeproj"
        try FileManager.default.createDirectory(atPath: outputProject, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationOutputProject: outputProject
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        let result = try await GenerateProjectAction().run(
            with: .init(force: false),
            context: context
        )

        #expect(result.generated == false)
        #expect(result.commandExecuted == nil)
        #expect(result.outputProject == outputProject)
        // No shell commands should have been executed
        #expect(commands().isEmpty)
    }

    // MARK: - Output verification failure

    @Test("throws when command succeeds but output project not created")
    func throwsWhenOutputNotCreated() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "Done\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationOutputProject: "/nonexistent/output/MockApp.xcodeproj"
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        await #expect(throws: ShipItError.self) {
            _ = try await GenerateProjectAction().run(with: .init(force: true), context: context)
        }
    }

    // MARK: - ensureProjectGenerated

    @Test("ensureProjectGenerated is a no-op when project generation is not configured")
    func ensureProjectGeneratedNoOpWithoutConfig() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        // Should not throw — no project generation configured
        try await context.ensureProjectGenerated()
    }

    @Test("ensureProjectGenerated is a no-op when auto_generate is disabled")
    func ensureProjectGeneratedSkipsWhenDisabled() async throws {
        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationAutoGenerate: false
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        // Should not throw or run commands
        try await context.ensureProjectGenerated()
        #expect(commands().isEmpty)
    }

    @Test("ensureProjectGenerated skips when output project already exists")
    func ensureProjectGeneratedSkipsWhenOutputExists() async throws {
        // Create a temp directory to act as the "output project"
        let dir = NSTemporaryDirectory() + "ShipItTests-\(UUID().uuidString)"
        let outputProject = dir + "/MockApp.xcodeproj"
        try FileManager.default.createDirectory(atPath: outputProject, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationOutputProject: outputProject,
            projectGenerationAutoGenerate: true
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", GenerateProjectAction.self),
            config: config,
            appStoreConnect: ascClient
        )

        // Should not run commands since project already exists
        try await context.ensureProjectGenerated()
        #expect(commands().isEmpty)
    }

    // MARK: - BuiltInSchemaCatalog

    @Test("BuiltInSchemaCatalog has generate_project action schema")
    func schemaCatalogEntry() {
        let schemas = BuiltInSchemaCatalog.actionSchemas()
        #expect(schemas.contains { $0.name == GenerateProjectAction.name })
    }

    @Test("BuiltInSchemaCatalog generate_project schema includes all option fields")
    func schemaCatalogFields() {
        let schema = BuiltInSchemaCatalog.optionSchema(for: GenerateProjectAction.name)
        let fieldNames = schema.map(\.name)
        #expect(fieldNames.contains("command"))
        #expect(fieldNames.contains("spec_path"))
        #expect(fieldNames.contains("output_project"))
        #expect(fieldNames.contains("force"))
    }

    @Test("BuiltInSchemaCatalog shipfileFields includes project_generation section")
    func shipfileFieldsIncludeProjectGeneration() {
        let fields = BuiltInSchemaCatalog.shipfileFields()
        let sectionNames = fields.map(\.name)
        #expect(sectionNames.contains("project_generation"))
    }

    @Test("project_generation section has expected property names")
    func projectGenerationSectionFields() {
        let fields = BuiltInSchemaCatalog.shipfileFields()
        guard let pgSection = fields.first(where: { $0.name == "project_generation" }) else {
            Issue.record("project_generation section not found in shipfileFields()")
            return
        }
        let propertyNames = pgSection.propertyValues.map(\.name)
        #expect(propertyNames.contains("tool"))
        #expect(propertyNames.contains("command"))
        #expect(propertyNames.contains("spec_path"))
        #expect(propertyNames.contains("output_project"))
        #expect(propertyNames.contains("auto_generate"))
    }
}

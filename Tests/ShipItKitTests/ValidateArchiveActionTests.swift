import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

// MARK: - ValidateArchiveAction Tests

@Suite("ValidateArchiveAction")
struct ValidateArchiveActionTests {

    // MARK: - Helpers

    private func mockContext() -> ActionContext {
        let (executor, _) = makeCaptureExecutor()
        return ActionContext.mock(executor: executor)
    }

    /// Creates a minimal valid .xcarchive structure at a temp path.
    private func makeXCArchive(
        infoPlistPresent: Bool = true,
        appBundlePresent: Bool = true,
        infoPlistContents: [String: Any]? = nil
    ) throws -> (archivePath: String, cleanup: () -> Void) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString)")
        let archivePath = tmp.path

        let productsApps = tmp
            .appendingPathComponent("Products")
            .appendingPathComponent("Applications")

        try FileManager.default.createDirectory(at: productsApps, withIntermediateDirectories: true)

        // Archive-level Info.plist
        if infoPlistPresent {
            let plist: [String: Any] = ["Name": "MyApp"]
            try (plist as NSDictionary).write(to: tmp.appendingPathComponent("Info.plist"))
        }

        // App bundle
        if appBundlePresent {
            let appBundle = productsApps.appendingPathComponent("MyApp.app")
            try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)

            let defaultPlist: [String: Any] = infoPlistContents ?? [
                "CFBundleIdentifier": "com.example.myapp",
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "42",
                "UIMainStoryboardFile": "Main",
                "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon"]]],
            ]
            try (defaultPlist as NSDictionary).write(to: appBundle.appendingPathComponent("Info.plist"))
        }

        return (archivePath, {
            try? FileManager.default.removeItem(at: tmp)
        })
    }

    // MARK: - Missing path

    @Test("throws invalidConfiguration when no path is provided and config has none")
    func missingPath() async throws {
        let context = mockContext()
        let options = ValidateArchiveAction.Options()

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    @Test("throws invalidConfiguration when the provided path does not exist")
    func pathNotFound() async throws {
        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: "/nonexistent/path/MyApp.xcarchive")

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    // MARK: - Valid archive

    @Test("passes a minimal valid xcarchive without errors")
    func validArchive() async throws {
        let (archivePath, cleanup) = try makeXCArchive()
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)
        let result = try await ValidateArchiveAction().run(with: options, context: context)

        #expect(result.passed)
        #expect(result.issues.filter { $0.severity == .error }.isEmpty)
        #expect(result.validatedPath == archivePath)
    }

    // MARK: - Archive structure errors

    @Test("throws validateArchiveFailed when Products directory is missing")
    func missingProductsThrows() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: tmp.path)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("ARCHIVE_MISSING_PRODUCTS") }
        }
    }

    @Test("reports ARCHIVE_MISSING_INFO_PLIST when archive-level Info.plist is missing")
    func missingArchiveInfoPlist() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistPresent: false)
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)
        // ARCHIVE_MISSING_INFO_PLIST is an error-level issue, so the action throws
        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("ARCHIVE_MISSING_INFO_PLIST") }
        }
    }

    @Test("throws validateArchiveFailed when no .app bundle exists inside Products/Applications/")
    func missingAppBundle() async throws {
        let (archivePath, cleanup) = try makeXCArchive(appBundlePresent: false)
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("ARCHIVE_NO_APP_BUNDLE") }
        }
    }

    // MARK: - Bundle Info.plist validation

    @Test("throws validateArchiveFailed when CFBundleIdentifier is missing")
    func missingBundleIdentifier() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("BUNDLE_MISSING_BUNDLE_ID") }
        }
    }

    @Test("throws validateArchiveFailed when CFBundleShortVersionString is missing")
    func missingMarketingVersion() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("BUNDLE_MISSING_MARKETING_VERSION") }
        }
    }

    @Test("throws validateArchiveFailed when CFBundleVersion is missing")
    func missingBuildNumber() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleShortVersionString": "1.0.0",
            "UIMainStoryboardFile": "Main",
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("BUNDLE_MISSING_BUILD_NUMBER") }
        }
    }

    @Test("reports warning when icon declaration is missing")
    func missingIconDeclaration() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)
        let result = try await ValidateArchiveAction().run(with: options, context: context)

        let iconIssue = result.issues.first { $0.code == "BUNDLE_MISSING_ICON_DECLARATION" }
        try #require(iconIssue != nil, "Expected BUNDLE_MISSING_ICON_DECLARATION warning")
        #expect(iconIssue?.severity == .warning)
        #expect(result.passed, "Missing icon should be a warning, not a validation failure")
    }

    @Test("throws validateArchiveFailed for invalid CFBundleIdentifier format")
    func invalidBundleIdentifier() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "not valid bundle id!",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("BUNDLE_INVALID_BUNDLE_ID") }
        }
    }

    // MARK: - iPad orientation

    @Test("throws validateArchiveFailed for missing iPad orientations without UIRequiresFullScreen")
    func iPadOrientationMissing() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                // Missing the other three
            ],
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("APPSTORE_ORIENTATION_IPAD") }
        }
    }

    @Test("passes iPad orientation check when UIRequiresFullScreen is true")
    func iPadOrientationFullScreen() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon"]]],
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
            ],
            "UIRequiresFullScreen": true,
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)
        let result = try await ValidateArchiveAction().run(with: options, context: context)

        #expect(!result.issues.contains { $0.code == "APPSTORE_ORIENTATION_IPAD" })
    }

    @Test("passes iPad orientation check when all four orientations are declared")
    func iPadOrientationAllFour() async throws {
        let (archivePath, cleanup) = try makeXCArchive(infoPlistContents: [
            "CFBundleIdentifier": "com.example.myapp",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "UIMainStoryboardFile": "Main",
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon"]]],
            "UISupportedInterfaceOrientations~ipad": [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight",
            ],
        ])
        defer { cleanup() }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(archivePath: archivePath)
        let result = try await ValidateArchiveAction().run(with: options, context: context)

        #expect(!result.issues.contains { $0.code == "APPSTORE_ORIENTATION_IPAD" })
    }

    // MARK: - IPA validation

    @Test("throws validateArchiveFailed for a non-ZIP file with .ipa extension")
    func ipaNotZip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString).ipa")
        try Data("not a zip file".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(ipaPath: tmp.path)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed(let issues) = error else { return false }
            return issues.contains { $0.contains("IPA_NOT_ZIP") }
        }
    }

    @Test("emits IPA_SHALLOW_VALIDATION warning for a valid-ZIP IPA")
    func ipaValidZipShallowWarning() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString).ipa")
        // Write ZIP magic bytes PK\x03\x04 + padding
        var zipHeader = Data([0x50, 0x4B, 0x03, 0x04])
        zipHeader.append(contentsOf: [UInt8](repeating: 0, count: 100))
        try zipHeader.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(ipaPath: tmp.path)
        // Should succeed (only warnings, no errors)
        let result = try await ValidateArchiveAction().run(with: options, context: context)

        #expect(result.issues.contains { $0.code == "IPA_SHALLOW_VALIDATION" && $0.severity == .warning })
    }

    // MARK: - failOnWarnings

    @Test("failOnWarnings causes throw when only warnings exist in a valid-ZIP IPA")
    func failOnWarningsIPA() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString).ipa")
        var zipHeader = Data([0x50, 0x4B, 0x03, 0x04])
        zipHeader.append(contentsOf: [UInt8](repeating: 0, count: 100))
        try zipHeader.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let context = mockContext()
        let options = ValidateArchiveAction.Options(ipaPath: tmp.path, failOnWarnings: true)

        await #expect {
            _ = try await ValidateArchiveAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.validateArchiveFailed = error else { return false }
            return true
        }
    }

    // MARK: - Action metadata

    @Test("action name is validate_archive")
    func actionName() {
        #expect(ValidateArchiveAction.name == "validate_archive")
    }

    @Test("BuiltInSchemaCatalog has validate_archive schema entry")
    func schemaCatalogEntry() {
        let schemas = BuiltInSchemaCatalog.actionSchemas()
        #expect(schemas.contains { $0.name == ValidateArchiveAction.name })
    }

    @Test("BuiltInSchemaCatalog validate_archive schema includes archive_path and ipa_path fields")
    func schemaCatalogFields() {
        let schema = BuiltInSchemaCatalog.optionSchema(for: ValidateArchiveAction.name)
        let fieldNames = schema.map(\.name)
        #expect(fieldNames.contains("archive_path"))
        #expect(fieldNames.contains("ipa_path"))
        #expect(fieldNames.contains("fail_on_warnings"))
    }
}

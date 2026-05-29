import Foundation
import Testing

@testable import ShipItKit

// Direct, rule-by-rule coverage for the semantic validation rules in
// `ActionValidationRules.swift`. These are otherwise only exercised indirectly
// through `ShipfileValidator`.

private func makeContext(
    options: [String: JSONValue] = [:],
    config: ResolvedConfig = ResolvedConfig(),
    stepIndex: Int = 0,
    allSteps: [WorkflowStepConfig] = []
) -> ActionValidationContext {
    ActionValidationContext(
        options: options,
        stepIndex: stepIndex,
        allSteps: allSteps,
        config: config
    )
}

/// Evaluates a rule set and returns the first issue produced (respecting platform scope).
private func firstIssue(
    _ rules: [ActionValidationRule],
    _ context: ActionValidationContext
) -> ValidationIssue? {
    rules.lazy.compactMap { $0.evaluate(context: context) }.first
}

@Suite("ActionValidationRules — cross-platform")
struct ActionValidationRulesCrossPlatformTests {

    // MARK: requiresScheme (BuildAction / TestAction / ArchiveAction)

    @Test("requiresScheme errors when neither option nor app.scheme is present (iOS)")
    func requiresSchemeErrors() {
        let issue = firstIssue(BuildAction.validationRules, makeContext(config: ResolvedConfig(platform: .ios)))
        #expect(issue?.severity == .error)
        #expect(issue?.path == ".options.scheme")
    }

    @Test("requiresScheme passes when app.scheme is configured")
    func requiresSchemePassesWithConfig() {
        let issue = firstIssue(
            BuildAction.validationRules,
            makeContext(config: ResolvedConfig(appScheme: "App", platform: .ios))
        )
        #expect(issue == nil)
    }

    @Test("requiresScheme passes when scheme is set at the step level")
    func requiresSchemePassesWithOption() {
        let issue = firstIssue(
            BuildAction.validationRules,
            makeContext(options: ["scheme": .string("App")], config: ResolvedConfig(platform: .ios))
        )
        #expect(issue == nil)
    }

    @Test("requiresScheme is skipped on android (platform scope)")
    func requiresSchemeSkippedOnAndroid() {
        let issue = firstIssue(
            BuildAction.validationRules,
            makeContext(config: ResolvedConfig(platform: .android))
        )
        #expect(issue == nil)
    }

    // MARK: VersionAction

    @Test("version bump=set requires an explicit version")
    func versionSetRequiresVersion() {
        let issue = firstIssue(VersionAction.validationRules, makeContext(options: ["bump": .string("set")]))
        #expect(issue?.severity == .error)
        #expect(issue?.path == ".options.version")
    }

    @Test("version bump=set passes when a version is supplied")
    func versionSetPassesWithVersion() {
        let issue = firstIssue(
            VersionAction.validationRules,
            makeContext(options: ["bump": .string("set"), "version": .string("1.2.3")])
        )
        #expect(issue == nil)
    }

    @Test("version bump=patch does not require a version")
    func versionPatchPasses() {
        let issue = firstIssue(VersionAction.validationRules, makeContext(options: ["bump": .string("patch")]))
        #expect(issue == nil)
    }

    // MARK: NotifyAction

    @Test("notify with no destination warns about being a no-op")
    func notifyNoDestinationWarns() {
        let issue = firstIssue(NotifyAction.validationRules, makeContext())
        #expect(issue?.severity == .warning)
    }

    @Test("notify with a webhook_url passes")
    func notifyWithWebhookPasses() {
        let issue = firstIssue(
            NotifyAction.validationRules,
            makeContext(options: ["webhook_url": .string("https://hooks.example.com/x")])
        )
        #expect(issue == nil)
    }

    // MARK: GitAction

    @Test("git tag requires tag_name")
    func gitTagRequiresName() {
        let issue = firstIssue(GitAction.validationRules, makeContext(options: ["operation": .string("tag")]))
        #expect(issue?.path == ".options.tag_name")
    }

    @Test("git commit requires commit_message")
    func gitCommitRequiresMessage() {
        let issue = firstIssue(GitAction.validationRules, makeContext(options: ["operation": .string("commit")]))
        #expect(issue?.path == ".options.commit_message")
    }

    @Test("git tag passes when tag_name is supplied")
    func gitTagPasses() {
        let issue = firstIssue(
            GitAction.validationRules,
            makeContext(options: ["operation": .string("tag"), "tag_name": .string("v1.0.0")])
        )
        #expect(issue == nil)
    }
}

#if os(macOS)
@Suite("ActionValidationRules — iOS-only actions")
struct ActionValidationRulesIOSTests {

    private let ios = ResolvedConfig(platform: .ios)

    // MARK: ExportAction

    @Test("export errors when no archive path is resolvable")
    func exportRequiresArchivePath() {
        let issue = firstIssue(ExportAction.validationRules, makeContext(config: ios))
        #expect(issue?.severity == .error)
        #expect(issue?.path == ".options.archive_path")
    }

    @Test("export passes when archive_path option is present")
    func exportPassesWithOption() {
        let issue = firstIssue(
            ExportAction.validationRules,
            makeContext(options: ["archive_path": .string("./build/App.xcarchive")], config: ios)
        )
        #expect(issue == nil)
    }

    // MARK: UploadAction

    @Test("upload errors when bundle_id is missing")
    func uploadRequiresBundleID() {
        let issue = firstIssue(UploadAction.validationRules, makeContext(config: ios))
        #expect(issue?.severity == .error)
    }

    @Test("upload errors when there is no ipa_path and no export context")
    func uploadRequiresIPAOrExport() {
        let config = ResolvedConfig(bundleID: "com.example.app", platform: .ios)
        let issue = firstIssue(UploadAction.validationRules, makeContext(config: config))
        #expect(issue?.path == ".options.ipa_path")
    }

    @Test("upload passes when a previous export step exists")
    func uploadPassesWithPriorExportStep() {
        let config = ResolvedConfig(bundleID: "com.example.app", platform: .ios)
        let steps = [
            WorkflowStepConfig(action: "export"),
            WorkflowStepConfig(action: "upload"),
        ]
        let issue = firstIssue(
            UploadAction.validationRules,
            makeContext(config: config, stepIndex: 1, allSteps: steps)
        )
        #expect(issue == nil)
    }

    // MARK: SignAction

    @Test("sign sync requires git_url")
    func signSyncRequiresGitURL() {
        let issue = firstIssue(
            SignAction.validationRules,
            makeContext(options: ["operation": .string("sync")], config: ios)
        )
        #expect(issue?.path == ".options.git_url")
    }

    @Test("sign import requires p12_path and provisioning_profile_path")
    func signImportRequiresAssets() {
        // With git_url provided so the first rule passes, the import-specific rules fire.
        let issue = firstIssue(
            SignAction.validationRules,
            makeContext(
                options: ["operation": .string("import"), "git_url": .string("git@example.com:certs.git")],
                config: ios
            )
        )
        #expect(issue?.path == ".options.p12_path")
    }

    @Test("sign cleanup needs no git_url")
    func signCleanupPasses() {
        let issue = firstIssue(
            SignAction.validationRules,
            makeContext(options: ["operation": .string("cleanup")], config: ios)
        )
        #expect(issue == nil)
    }

    // MARK: SnapshotAction

    @Test("snapshot requires a scheme")
    func snapshotRequiresScheme() {
        let issue = firstIssue(
            SnapshotAction.validationRules,
            makeContext(options: ["devices": .array([.string("iPhone 16")])], config: ios)
        )
        #expect(issue?.path == ".options.scheme")
    }

    @Test("snapshot requires at least one device")
    func snapshotRequiresDevice() {
        let config = ResolvedConfig(appScheme: "App", platform: .ios)
        let issue = firstIssue(SnapshotAction.validationRules, makeContext(config: config))
        #expect(issue?.path == ".options.devices")
    }

    @Test("snapshot passes with scheme and devices")
    func snapshotPasses() {
        let config = ResolvedConfig(appScheme: "App", platform: .ios)
        let issue = firstIssue(
            SnapshotAction.validationRules,
            makeContext(options: ["devices": .array([.string("iPhone 16")])], config: config)
        )
        #expect(issue == nil)
    }

    // MARK: ProvisionAction

    @Test("provision createAppId requires bundle_id")
    func provisionCreateAppIdRequiresBundleID() {
        let issue = firstIssue(
            ProvisionAction.validationRules,
            makeContext(options: ["operation": .string("createAppId")], config: ios)
        )
        #expect(issue?.path == ".options.bundle_id")
    }

    @Test("provision registerDevices requires at least one UDID")
    func provisionRegisterDevicesRequiresUDID() {
        let issue = firstIssue(
            ProvisionAction.validationRules,
            makeContext(options: ["operation": .string("registerDevices")], config: ios)
        )
        #expect(issue?.path == ".options.device_udids")
    }

    // MARK: DsymAction

    @Test("dsym upload requires dsym_path")
    func dsymUploadRequiresPath() {
        let issue = firstIssue(
            DsymAction.validationRules,
            makeContext(options: ["operation": .string("upload")], config: ios)
        )
        #expect(issue?.path == ".options.dsym_path")
    }

    @Test("dsym upload passes when dsym_path and upload_url are supplied")
    func dsymUploadPasses() {
        let issue = firstIssue(
            DsymAction.validationRules,
            makeContext(
                options: [
                    "operation": .string("upload"),
                    "dsym_path": .string("./App.dSYM"),
                    "upload_url": .string("https://upload.example.com"),
                ],
                config: ios
            )
        )
        #expect(issue == nil)
    }
}
#endif

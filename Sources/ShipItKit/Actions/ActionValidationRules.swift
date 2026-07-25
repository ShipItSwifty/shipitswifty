import Foundation

// MARK: - Built-in semantic validation rules
//
// Each action declares its validation rules as a static property so they can be
// passed to `descriptor(for:validationRules:)` at registration time.
//
// Rules are evaluated by `ShipfileValidator` for every workflow step that
// references the action.  Platform-scoped rules are skipped automatically when
// the resolved platform does not match.
//
// Helpers at the bottom of this file are shared across multiple rule sets.

// MARK: BuildAction

extension BuildAction {
    public static var validationRules: [ActionValidationRule] {
        [
            .requiresScheme(for: [.ios])
        ]
    }
}

// MARK: TestAction

extension TestAction {
    public static var validationRules: [ActionValidationRule] {
        [
            .requiresScheme(for: [.ios])
        ]
    }
}

// MARK: ArchiveAction

extension ArchiveAction {
    public static var validationRules: [ActionValidationRule] {
        [
            .requiresScheme(for: [.ios])
        ]
    }
}

// MARK: ExportAction

#if os(macOS)
extension ExportAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard
                    ctx.options["archive_path"]?.stringValue == nil,
                    ctx.config.exportArchivePath == nil,
                    ctx.config.archiveOutputPath == nil
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.archive_path",
                    message: "Export requires an archive path or archive.output_path.")
            }
        ]
    }
}

// MARK: UploadAction

extension UploadAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.config.bundleID == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: "$",
                    message: "This action requires app.bundle_id or SHIPIT_APP__BUNDLE_ID.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard
                    ctx.options["ipa_path"]?.stringValue == nil,
                    !ctx.hasExportContext
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.ipa_path",
                    message: "Upload needs `ipa_path`, a previous export step, or an IPA already present in the export output directory.")
            },
        ]
    }
}

// MARK: TestFlightAction

extension TestFlightAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.config.bundleID == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: "$",
                    message: "This action requires app.bundle_id or SHIPIT_APP__BUNDLE_ID.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard
                    ctx.options["ipa"]?.stringValue == nil,
                    !ctx.hasExportContext
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.ipa",
                    message: "TestFlight needs `ipa`, a previous export step, or an IPA already present in the export output directory.")
            },
        ]
    }
}

// MARK: MetadataAction

extension MetadataAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.config.bundleID == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: "$",
                    message: "This action requires app.bundle_id or SHIPIT_APP__BUNDLE_ID.")
            }
        ]
    }
}

// MARK: SignAction

extension SignAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                let operation = ctx.options["operation"]?.stringValue ?? ""
                guard ["sync", "import", "init"].contains(operation) else { return nil }
                guard
                    ctx.options["git_url"]?.stringValue == nil,
                    ctx.config.codeSigningGitUrl == nil
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.git_url",
                    message: "This sign operation requires git_url or code_signing.git_url.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "import" else { return nil }
                guard ctx.options["p12_path"]?.stringValue == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.p12_path",
                    message: "sign import requires p12_path.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "import" else { return nil }
                guard ctx.options["provisioning_profile_path"]?.stringValue == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.provisioning_profile_path",
                    message: "sign import requires provisioning_profile_path.")
            },
        ]
    }
}

// MARK: SnapshotAction

extension SnapshotAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard
                    ctx.options["scheme"]?.stringValue == nil,
                    ctx.config.screenshotScheme == nil,
                    ctx.config.appScheme == nil
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.scheme",
                    message: "Snapshot requires screenshots.scheme, app.scheme, or a step-level scheme.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                let devices = ctx.options["devices"]?.arrayValue ?? []
                guard devices.isEmpty && ctx.config.screenshotDevices.isEmpty else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.devices",
                    message: "Snapshot requires at least one device.")
            },
        ]
    }
}

// MARK: ProvisionAction

extension ProvisionAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "createAppId" else { return nil }
                guard ctx.options["bundle_id"]?.stringValue == nil, ctx.config.bundleID == nil else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.bundle_id",
                    message: "createAppId requires bundle_id or app.bundle_id.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "registerDevices" else { return nil }
                let udids = ctx.options["device_udids"]?.arrayValue ?? []
                guard udids.isEmpty else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.device_udids",
                    message: "registerDevices requires at least one device UDID.")
            },
        ]
    }
}

// MARK: DsymAction

extension DsymAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "upload" else { return nil }
                guard ctx.options["dsym_path"]?.stringValue == nil else { return nil }
                return ValidationIssue(severity: .error, path: ".options.dsym_path", message: "dSYM upload requires dsym_path.")
            },
            ActionValidationRule(platforms: [.ios]) { ctx in
                guard ctx.options["operation"]?.stringValue == "upload" else { return nil }
                guard ctx.options["upload_url"]?.stringValue == nil else { return nil }
                return ValidationIssue(severity: .error, path: ".options.upload_url", message: "dSYM upload requires upload_url.")
            },
        ]
    }
}
#endif

// MARK: GitAction

extension GitAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule { ctx in
                guard ctx.options["operation"]?.stringValue == "tag" else { return nil }
                guard ctx.options["tag_name"]?.stringValue == nil else { return nil }
                return ValidationIssue(severity: .error, path: ".options.tag_name", message: "git tag requires tag_name.")
            },
            ActionValidationRule { ctx in
                guard ctx.options["operation"]?.stringValue == "commit" else { return nil }
                guard ctx.options["commit_message"]?.stringValue == nil else { return nil }
                return ValidationIssue(severity: .error, path: ".options.commit_message", message: "git commit requires commit_message.")
            },
        ]
    }
}

// MARK: VersionAction

extension VersionAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule { ctx in
                guard
                    ctx.options["bump"]?.stringValue == "set",
                    ctx.options["version"]?.stringValue == nil
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.version",
                    message: "version bump `set` requires an explicit version value.")
            }
        ]
    }
}

// MARK: NotifyAction

extension NotifyAction {
    public static var validationRules: [ActionValidationRule] {
        [
            ActionValidationRule { ctx in
                guard ctx.options["slack"] == nil, ctx.options["webhook_url"]?.stringValue == nil else { return nil }
                return ValidationIssue(
                    severity: .warning,
                    path: ".options",
                    message: "notify has no configured destination and will be a no-op.")
            }
        ]
    }
}

// MARK: FirebaseAppDistributionAction

extension FirebaseAppDistributionAction {
    public static var validationRules: [ActionValidationRule] {
        [
            // `app_id` is required, but an unexpanded `${VAR}` reference is legitimate at
            // validation time — CI supplies it at run time — so only a literal absence fails.
            ActionValidationRule { ctx in
                guard ctx.options["app_id"]?.stringValue?.isEmpty ?? true else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.app_id",
                    message:
                        "firebase-app-distribution requires an explicit `app_id` (e.g. ${FIREBASE_IOS_QA_APP_ID}).")
            },
            ActionValidationRule { ctx in
                guard ctx.options["artifact_path"]?.stringValue?.isEmpty ?? true else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.artifact_path",
                    message: "firebase-app-distribution requires an `artifact_path` to the signed .ipa or .apk.")
            },
            // A release with no audience uploads successfully but reaches nobody.
            ActionValidationRule { ctx in
                let hasGroups = !(ctx.options["groups"]?.arrayValue?.isEmpty ?? true)
                let hasTesters = !(ctx.options["testers"]?.arrayValue?.isEmpty ?? true)
                guard !hasGroups, !hasTesters else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options",
                    message:
                        "firebase-app-distribution needs at least one `groups` alias or `testers` email, otherwise the release reaches no one."
                )
            },
            // Catches a production .aab or a swapped-platform artifact wired into the step.
            ActionValidationRule { ctx in
                guard let path = ctx.options["artifact_path"]?.stringValue,
                    !path.isEmpty,
                    !path.contains("${")
                else { return nil }
                let ext = (path as NSString).pathExtension.lowercased()
                guard !["ipa", "apk", "aab"].contains(ext) else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.artifact_path",
                    message:
                        "firebase-app-distribution can only distribute .ipa, .apk, or .aab artifacts — '\(path)' is not one.")
            },
            // Credentials must come from CI, never from the committed Shipfile.
            ActionValidationRule { ctx in
                guard let path = ctx.options["service_account_path"]?.stringValue,
                    path.trimmingCharacters(in: .whitespaces).hasPrefix("{")
                else { return nil }
                return ValidationIssue(
                    severity: .error,
                    path: ".options.service_account_path",
                    message:
                        "firebase-app-distribution: `service_account_path` must be a path, not inline credential JSON. Store the key in CI secret storage."
                )
            },
        ]
    }
}

// MARK: - Built-in rule lookup

/// Maps built-in action names to their semantic validation rules.
///
/// `shipit validate yml` builds its action descriptors from ``BuiltInSchemaCatalog`` rather
/// than from the run-time registry, so it has no action *types* to read `validationRules`
/// from. This table is the bridge: without it, every rule in this file would be evaluated
/// only on the `shipit run` path and silently skipped during validation.
public enum BuiltInValidationRules {
    /// Returns the validation rules registered for a built-in action name.
    ///
    /// - Parameter actionName: The registered action name (e.g. `"archive"`, `"version"`).
    /// - Returns: The action's rules, or an empty array when the name has none.
    public static func rules(for actionName: String) -> [ActionValidationRule] {
        byActionName[actionName] ?? []
    }

    /// All built-in rules, keyed by action name.
    ///
    /// The Apple-only actions above are declared inside `#if os(macOS)`, so their rules can only
    /// be referenced there. On Linux those action names simply carry no semantic rules, which
    /// matches the fact that the actions themselves are unavailable.
    public static let byActionName: [String: [ActionValidationRule]] = {
        var rules: [String: [ActionValidationRule]] = [
            ArchiveAction.name: ArchiveAction.validationRules,
            BuildAction.name: BuildAction.validationRules,
            FirebaseAppDistributionAction.name: FirebaseAppDistributionAction.validationRules,
            GitAction.name: GitAction.validationRules,
            NotifyAction.name: NotifyAction.validationRules,
            TestAction.name: TestAction.validationRules,
            VersionAction.name: VersionAction.validationRules,
        ]
        #if os(macOS)
        rules[DsymAction.name] = DsymAction.validationRules
        rules[ExportAction.name] = ExportAction.validationRules
        rules[MetadataAction.name] = MetadataAction.validationRules
        rules[ProvisionAction.name] = ProvisionAction.validationRules
        rules[SignAction.name] = SignAction.validationRules
        rules[SnapshotAction.name] = SnapshotAction.validationRules
        rules[TestFlightAction.name] = TestFlightAction.validationRules
        rules[UploadAction.name] = UploadAction.validationRules
        #endif
        return rules
    }()
}

// MARK: - Shared helpers

extension ActionValidationRule {
    /// Returns a rule that requires `app.scheme` or a step-level `scheme` option,
    /// scoped to the given platforms.
    static func requiresScheme(for platforms: Set<Platform>) -> ActionValidationRule {
        ActionValidationRule(platforms: platforms) { ctx in
            guard
                ctx.options["scheme"]?.stringValue == nil,
                ctx.config.appScheme == nil
            else { return nil }
            return ValidationIssue(
                severity: .error,
                path: ".options.scheme",
                message: "This action requires a scheme or app.scheme in config.")
        }
    }
}

extension ActionValidationContext {
    /// Returns `true` if a previous step in this workflow was `export`, or if
    /// an IPA already exists in the configured export output directory.
    var hasExportContext: Bool {
        if allSteps[..<stepIndex].contains(where: { $0.action.lowercased() == "export" }) {
            return true
        }
        let outputDirectory = config.exportOutputDirectory ?? "./build/export"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: outputDirectory) else {
            return false
        }
        return contents.contains(where: { $0.hasSuffix(".ipa") })
    }
}

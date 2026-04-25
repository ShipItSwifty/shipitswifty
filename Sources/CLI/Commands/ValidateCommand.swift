import ArgumentParser
import ShipItKit

/// Top-level `shipit validate` command — delegates to subcommands.
///
/// Running `shipit validate` without a subcommand is equivalent to `shipit validate yml`.
struct ValidateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: "Validate Shipfile, App Store metadata, archive readiness, and Android bundles",
    discussion: """
      SUBCOMMANDS:
        yml        Validate Shipfile structure and workflow semantics (default)
        metadata   Validate App Store metadata and precheck rules (iOS)
        archive    Validate xcarchive / ipa / app bundle for upload readiness (iOS)
        bundle     Validate Android App Bundle (.aab) or APK for Play Store readiness (Android)
        all        Run all validation stages in sequence
      """,
    subcommands: [
      ValidateYmlCommand.self,
      ValidateMetadataCommand.self,
      ValidateArchiveCommand.self,
      ValidateBundleCommand.self,
      ValidateAllCommand.self,
    ],
    defaultSubcommand: ValidateYmlCommand.self
  )
}

// MARK: - validate yml

/// Validate Shipfile structure, workflow semantics, and config completeness.
///
/// This is the default when running `shipit validate` without a subcommand.
struct ValidateYmlCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "yml",
    abstract: "Validate Shipfile structure and workflow semantics"
  )

  @OptionGroup var global: GlobalOptions

  func run() async throws {
    let report = await ShipfileValidator().validate(
      shipfilePath: configuredShipfilePath(from: global),
      actionDescriptors: builtInActionDescriptors()
    )

    switch global.output {
    case .json:
      let reporter = JSONReporter()
      let status = report.isValid ? "success" : "failure"
      print(
        try reporter.encode(
          ActionResultEnvelope(
            action: "validate",
            status: status,
            payload: validateYmlPayload(report: report)
          )))
    case .human:
      let formatter = makeHumanFormatter(global: global)
      formatter.printHeader("Validate: Shipfile (yml)")
      formatter.printKV("Shipfile", report.shipfilePath)
      if report.issues.isEmpty {
        formatter.printSuccess("No validation issues found")
      } else {
        for issue in report.issues {
          let line = "\(issue.path): \(issue.message)"
          switch issue.severity {
          case .error: formatter.printError(line)
          case .warning: formatter.printWarning(line)
          }
        }
      }
    }

    if !report.isValid {
      throw ExitCode(2)
    }
  }
}

// MARK: - validate metadata

/// Validate App Store metadata against precheck rules.
///
/// Checks text lengths, forbidden words, and other metadata guidelines.
/// Equivalent to the legacy `shipit precheck` command.
struct ValidateMetadataCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "metadata",
    abstract: "Validate App Store metadata and precheck rules"
  )

  @OptionGroup var global: GlobalOptions

  @Option(name: .long, help: "Local directory containing metadata files")
  var directory: String?

  @Flag(name: .long, help: "Fail on warnings in addition to errors")
  var failOnWarnings: Bool = false

  func run() async throws {
    do {
      let config = try await resolveRequiredConfig(
        global: global,
        cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
      )
      let context = try await buildActionContext(config: config)

      let options = PrecheckAction.Options(
        directory: directory,
        failOnWarnings: failOnWarnings ? true : nil
      )

      let result = try await PrecheckAction().run(with: options, context: context)

      switch global.output {
      case .json:
        let reporter = JSONReporter()
        print(
          try reporter.encode(
            ActionResultEnvelope(
              action: "validate",
              status: "success",
              payload: .object([
                "mode": .string("metadata"),
                "issues": .array(
                  result.warnings.map {
                    .object([
                      "severity": .string("warning"),
                      "code": .string("METADATA_WARNING"),
                      "message": .string($0),
                    ])
                  }),
              ])
            )))
      case .human:
        outputResult(
          action: "validate metadata", result: result, format: global.output,
          colorMode: global.effectiveColorMode)
      }
    } catch let error as ShipItError {
      switch global.output {
      case .json:
        if case .precheckFailed(let violations) = error {
          let reporter = JSONReporter()
          print(
            try reporter.encode(
              ActionResultEnvelope(
                action: "validate",
                status: "failure",
                payload: .object([
                  "mode": .string("metadata"),
                  "issues": .array(
                    violations.map {
                      .object([
                        "severity": .string("error"),
                        "code": .string("METADATA_VIOLATION"),
                        "message": .string($0),
                      ])
                    }),
                ])
              )))
        } else {
          outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
        }
      case .human:
        outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
      }
      throw ExitCode(error.exitCode)
    }
  }
}

// MARK: - validate archive

/// Validate a `.xcarchive` or `.ipa` for App Store upload readiness.
///
/// Catches common issues before upload: invalid icon transparency, missing
/// Info.plist keys, iPad orientation requirements, and archive structure problems.
struct ValidateArchiveCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "archive",
    abstract: "Validate xcarchive / ipa / app bundle for upload readiness"
  )

  @OptionGroup var global: GlobalOptions

  @Option(name: .long, help: "Path to .xcarchive directory to validate")
  var archivePath: String?

  @Option(name: .long, help: "Path to .ipa file to validate")
  var ipa: String?

  @Flag(name: .long, help: "Fail on warnings in addition to errors")
  var failOnWarnings: Bool = false

  func run() async throws {
    do {
      let context = try await buildFallbackActionContext(platform: global.platform ?? .ios)

      let options = ValidateArchiveAction.Options(
        archivePath: archivePath,
        ipaPath: ipa,
        failOnWarnings: failOnWarnings ? true : nil
      )

      let result = try await ValidateArchiveAction().run(with: options, context: context)

      switch global.output {
      case .json:
        let reporter = JSONReporter()
        print(
          try reporter.encode(
            ActionResultEnvelope(
              action: "validate",
              status: result.passed ? "success" : "failure",
              payload: validateArchivePayload(result: result)
            )))
      case .human:
        let formatter = makeHumanFormatter(global: global)
        formatter.printHeader("Validate: Archive")
        formatter.printKV("Path", result.validatedPath)
        if result.issues.isEmpty {
          formatter.printSuccess("No archive issues found")
        } else {
          for issue in result.issues {
            let line = "[\(issue.code)] \(issue.message)"
            switch issue.severity {
            case .error: formatter.printError(line)
            case .warning: formatter.printWarning(line)
            }
          }
        }
      }
    } catch let error as ShipItError {
      switch global.output {
      case .json:
        if case .validateArchiveFailed(let issues) = error {
          let reporter = JSONReporter()
          print(
            try reporter.encode(
              ActionResultEnvelope(
                action: "validate",
                status: "failure",
                payload: .object([
                  "mode": .string("archive"),
                  "issues": .array(
                    issues.map {
                      .object([
                        "severity": .string("error"),
                        "code": .string("ARCHIVE_ERROR"),
                        "message": .string($0),
                      ])
                    }),
                ])
              )))
        } else {
          outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
        }
      case .human:
        outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
      }
      throw ExitCode(error.exitCode)
    }
  }
}

// MARK: - validate bundle

/// Validate an Android App Bundle (.aab) or APK for Google Play upload readiness.
///
/// Checks file format integrity and runs `bundletool validate` if available.
struct ValidateBundleCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Validate Android App Bundle (.aab) or APK for Google Play upload readiness"
  )

  @OptionGroup var global: GlobalOptions

  @Option(name: .long, help: "Path to .aab file to validate")
  var aab: String?

  @Option(name: .long, help: "Path to .apk file to validate")
  var apk: String?

  @Flag(name: .long, help: "Fail on warnings in addition to errors")
  var failOnWarnings: Bool = false

  func run() async throws {
    do {
      let config = try await resolveRequiredConfig(
        global: global,
        cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
      )
      let context = try await buildActionContext(config: config)

      let options = ValidateBundleAction.Options(
        aabPath: aab,
        apkPath: apk,
        failOnWarnings: failOnWarnings ? true : nil
      )

      let result = try await ValidateBundleAction().run(with: options, context: context)

      switch global.output {
      case .json:
        let reporter = JSONReporter()
        print(
          try reporter.encode(
            ActionResultEnvelope(
              action: "validate",
              status: result.passed ? "success" : "failure",
              payload: validateBundlePayload(result: result)
            )))
      case .human:
        let formatter = makeHumanFormatter(global: global)
        formatter.printHeader("Validate: Bundle")
        formatter.printKV("Path", result.validatedPath)
        formatter.printKV("Type", result.isAAB ? "AAB" : "APK")
        if result.issues.isEmpty {
          formatter.printSuccess("No bundle issues found")
        } else {
          for issue in result.issues {
            let line = "[\(issue.code)] \(issue.message)"
            switch issue.severity {
            case .error: formatter.printError(line)
            case .warning: formatter.printWarning(line)
            }
          }
        }
      }
    } catch let error as ShipItError {
      outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
      throw ExitCode(error.exitCode)
    }
  }
}

// MARK: - validate all

/// Run all validation stages in sequence: yml → metadata → archive.
///
/// Fails fast on the first blocking error.
struct ValidateAllCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "all",
    abstract: "Run all validation stages: yml, metadata, and archive"
  )

  @OptionGroup var global: GlobalOptions

  @Option(name: .long, help: "Metadata directory (for metadata stage)")
  var directory: String?

  @Option(name: .long, help: "Path to .xcarchive (for archive stage)")
  var archivePath: String?

  @Option(name: .long, help: "Path to .ipa (for archive stage)")
  var ipa: String?

  @Flag(name: .long, help: "Fail on warnings in addition to errors")
  var failOnWarnings: Bool = false

  func run() async throws {
    let formatter = makeHumanFormatter(global: global)

    // --- Stage 1: yml ---
    if global.output == .human { formatter.print("Stage 1/3: validate yml") }
    let ymlReport = await ShipfileValidator().validate(
      shipfilePath: configuredShipfilePath(from: global),
      actionDescriptors: builtInActionDescriptors()
    )

    if !ymlReport.isValid {
      emitAllFailure(
        stage: "yml", detail: "Shipfile validation failed", format: global.output,
        formatter: formatter, report: ymlReport)
      throw ExitCode(2)
    }
    if global.output == .human { formatter.printSuccess("yml: passed") }

    // --- Stage 2: metadata ---
    if global.output == .human { formatter.print("Stage 2/3: validate metadata") }
    do {
      let config = try await resolveRequiredConfig(
        global: global,
        cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
      )
      let context = try await buildActionContext(config: config)
      let precheckOptions = PrecheckAction.Options(
        directory: directory, failOnWarnings: failOnWarnings ? true : nil)
      _ = try await PrecheckAction().run(with: precheckOptions, context: context)
      if global.output == .human { formatter.printSuccess("metadata: passed") }

      // --- Stage 3: archive ---
      if global.output == .human { formatter.print("Stage 3/3: validate archive") }
      let archiveOptions = ValidateArchiveAction.Options(
        archivePath: archivePath,
        ipaPath: ipa,
        failOnWarnings: failOnWarnings ? true : nil
      )
      let archiveResult = try await ValidateArchiveAction().run(
        with: archiveOptions, context: context)
      if global.output == .human { formatter.printSuccess("archive: passed") }

      // All stages passed
      switch global.output {
      case .json:
        let reporter = JSONReporter()
        print(
          try reporter.encode(
            ActionResultEnvelope(
              action: "validate",
              status: "success",
              payload: .object([
                "mode": .string("all"),
                "stages": .array([.string("yml"), .string("metadata"), .string("archive")]),
                "archive": validateArchivePayload(result: archiveResult),
                "yml": validateYmlPayload(report: ymlReport),
              ])
            )))
      case .human:
        formatter.printSuccess("All validation stages passed.")
      }

    } catch let error as ShipItError {
      switch global.output {
      case .json:
        let reporter = JSONReporter()
        print(
          try reporter.encode(
            ActionResultEnvelope(
              action: "validate",
              status: "failure",
              payload: .object([
                "mode": .string("all"),
                "failedStage": .string(stageForError(error)),
                "error": .string(error.errorDescription ?? error.localizedDescription),
              ])
            )))
      case .human:
        outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
      }
      throw ExitCode(error.exitCode)
    }
  }

  private func emitAllFailure(
    stage: String, detail: String, format: OutputFormat, formatter: HumanFormatter,
    report: ValidationReport
  ) {
    switch format {
    case .json:
      let reporter = JSONReporter()
      if let encoded = try? reporter.encode(
        ActionResultEnvelope(
          action: "validate",
          status: "failure",
          payload: .object([
            "mode": .string("all"),
            "failedStage": .string(stage),
            "detail": validateYmlPayload(report: report),
          ])
        ))
      {
        print(encoded)
      }
    case .human:
      for issue in report.issues {
        let line = "\(issue.path): \(issue.message)"
        switch issue.severity {
        case .error: formatter.printError(line)
        case .warning: formatter.printWarning(line)
        }
      }
    }
  }

  private func stageForError(_ error: ShipItError) -> String {
    switch error {
    case .precheckFailed: return "metadata"
    case .validateArchiveFailed: return "archive"
    default: return "unknown"
    }
  }
}

// MARK: - Shared JSON payload builders

private func validateYmlPayload(report: ValidationReport) -> JSONValue {
  .object([
    "mode": .string("yml"),
    "shipfilePath": .string(report.shipfilePath),
    "isValid": .bool(report.isValid),
    "issues": .array(
      report.issues.map { issue in
        .object([
          "severity": .string(issue.severity.rawValue),
          "code": .string("YML_\(issue.severity.rawValue.uppercased())"),
          "path": .string(issue.path),
          "message": .string(issue.message),
        ])
      }),
  ])
}

private func validateArchivePayload(result: ValidateArchiveAction.Result) -> JSONValue {
  var fields: [String: JSONValue] = [
    "mode": .string("archive"),
    "validatedPath": .string(result.validatedPath),
    "passed": .bool(result.passed),
    "issues": .array(
      result.issues.map { issue in
        .object([
          "severity": .string(issue.severity.rawValue),
          "code": .string(issue.code),
          "message": .string(issue.message),
        ])
      }),
  ]
  if let bundleID = result.bundleID {
    fields["bundleId"] = .string(bundleID)
  }
  return .object(fields)
}

private func validateBundlePayload(result: ValidateBundleAction.Result) -> JSONValue {
  .object([
    "mode": .string("bundle"),
    "validatedPath": .string(result.validatedPath),
    "isAAB": .bool(result.isAAB),
    "passed": .bool(result.passed),
    "issues": .array(
      result.issues.map { issue in
        .object([
          "severity": .string(issue.severity.rawValue),
          "code": .string(issue.code),
          "message": .string(issue.message),
        ])
      }),
  ])
}

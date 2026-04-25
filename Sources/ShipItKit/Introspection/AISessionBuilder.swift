import Foundation

/// Builds a structured `AISessionPayload` from a project inspection.
///
/// This is the core logic behind `shipit ai-session`. It produces a stable,
/// versioned JSON payload containing everything an AI agent needs to guide a
/// user through configuring and running a ShipItSwifty workflow.
///
/// ## Usage
/// ```swift
/// let inspection = try await ProjectInspector(rootPath: path).inspect()
/// let payload = AISessionBuilder().build(goal: .beta, inspection: inspection, hasExistingShipfile: false)
/// ```
public struct AISessionBuilder: Sendable {

  /// The current contract version. Increment on breaking `AISessionPayload` changes.
  public static let contractVersion = "1"

  public init() {}

  /// Builds a full `AISessionPayload` for the given goal and inspection result.
  ///
  /// - Parameters:
  ///   - goal: The distribution goal (`local`, `beta`, or `release`).
  ///   - inspection: Project inspection result from `ProjectInspector`.
  ///   - hasExistingShipfile: Whether a Shipfile already exists at the target path.
  ///   - platform: Target platform. Defaults to `.ios`. When `.android`, the agent prompt and
  ///     secret descriptors are adapted for the Android/Google Play workflow.
  ///   - customActions: User-defined composite actions declared in `Shipfile.custom_actions`.
  public func build(
    goal: SuggestionGoal,
    inspection: ProjectInspection,
    hasExistingShipfile: Bool,
    platform: Platform = .ios,
    customActions: [String: CustomActionConfig] = [:]
  ) -> AISessionPayload {
    let suggestion = ShipfileSuggester().suggest(goal: goal, from: inspection)
    let app = inspection.suggestedAppConfig
    let appConfig = buildInferredConfig(app: app, inspection: inspection, goal: goal)
    let ambiguities = buildAmbiguities(inspection: inspection)
    let requiredSecrets = buildSecretDescriptors(for: goal, platform: platform)
    let readiness = buildReadiness(
      goal: goal,
      app: app,
      inspection: inspection,
      requiredSecrets: requiredSecrets,
      platform: platform
    )
    let nextAction = buildNextAction(
      goal: goal,
      hasExistingShipfile: hasExistingShipfile,
      readiness: readiness,
      missingValues: suggestion.missingValues,
      ambiguities: ambiguities,
      platform: platform
    )
    let agentPrompt = buildAgentPrompt(
      goal: goal, readiness: readiness, platform: platform, customActions: customActions)
    let nextQuestion = buildNextQuestion(
      goal: goal,
      missingValues: suggestion.missingValues,
      ambiguities: ambiguities,
      readiness: readiness,
      platform: platform
    )

    return AISessionPayload(
      version: Self.contractVersion,
      goal: goal.rawValue,
      appConfig: appConfig,
      missing: suggestion.missingValues,
      ambiguities: ambiguities,
      suggestedShipfile: suggestion.yaml,
      readiness: readiness,
      nextAction: nextAction,
      agentPrompt: agentPrompt,
      nextQuestion: nextQuestion
    )
  }

  // MARK: - Inferred config

  private func buildInferredConfig(
    app: ProjectInspection.SuggestedAppConfig,
    inspection: ProjectInspection,
    goal: SuggestionGoal
  ) -> [InferredConfigEntry] {
    var entries: [InferredConfigEntry] = []
    let allSchemes = inspection.schemes
    let runnableSchemes = allSchemes.filter(\.likelyRunnable)

    // workspace / project
    if let workspace = app.workspace {
      entries.append(
        .init(
          keyPath: "app.workspace",
          value: .string(workspace),
          source: .detected,
          confidence: .high,
          why: "Found .xcworkspace at \(workspace)"
        ))
    } else if let project = app.project {
      let conf: InferenceConfidence = inspection.xcodeContainers.count == 1 ? .high : .medium
      let why =
        inspection.xcodeContainers.count == 1
        ? "Found single .xcodeproj at \(project)"
        : "Multiple containers found; selected \(project) as the primary project"
      entries.append(
        .init(
          keyPath: "app.project", value: .string(project), source: .detected, confidence: conf,
          why: why))
    } else {
      entries.append(
        .init(
          keyPath: "app.workspace",
          value: nil,
          source: .unresolved,
          why: "No .xcworkspace or .xcodeproj found under the root path"
        ))
    }

    // scheme
    if let scheme = app.scheme {
      let containerBaseName = inspection.xcodeContainers.first
        .map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }
      let isExactNameMatch = containerBaseName == scheme
      let conf: InferenceConfidence
      let why: String
      if isExactNameMatch && runnableSchemes.count == 1 {
        conf = .high
        why = "Scheme '\(scheme)' matches the container name and is the only runnable scheme"
      } else if isExactNameMatch {
        conf = .high
        why = "Scheme '\(scheme)' matches the container name and is runnable"
      } else if runnableSchemes.count == 1 {
        conf = .medium
        why = "'\(scheme)' is the only runnable scheme (excludes test/watch/clip/package schemes)"
      } else {
        conf = .medium
        why =
          "'\(scheme)' chosen as first runnable scheme among \(runnableSchemes.count) candidates"
      }
      entries.append(
        .init(
          keyPath: "app.scheme", value: .string(scheme), source: .detected, confidence: conf,
          why: why))
    } else {
      let why =
        allSchemes.isEmpty
        ? "No schemes found in container"
        : "No runnable scheme could be selected from \(allSchemes.count) discovered schemes"
      entries.append(.init(keyPath: "app.scheme", value: nil, source: .unresolved, why: why))
    }

    // bundle_id
    if let bundleID = app.bundleID {
      entries.append(
        .init(
          keyPath: "app.bundle_id",
          value: .string(bundleID),
          source: .detected,
          confidence: .high,
          why:
            "Read PRODUCT_BUNDLE_IDENTIFIER from xcodebuild -showBuildSettings for the selected scheme"
        ))
    } else {
      entries.append(
        .init(
          keyPath: "app.bundle_id",
          value: nil,
          source: .unresolved,
          why: "PRODUCT_BUNDLE_IDENTIFIER could not be read from build settings"
        ))
    }

    // team_id
    if let teamID = app.teamID {
      entries.append(
        .init(
          keyPath: "app.team_id",
          value: .string(teamID),
          source: .detected,
          confidence: .high,
          why: "Read DEVELOPMENT_TEAM from xcodebuild -showBuildSettings for the selected scheme"
        ))
    } else {
      entries.append(
        .init(
          keyPath: "app.team_id",
          value: nil,
          source: .unresolved,
          why: "DEVELOPMENT_TEAM could not be read from build settings"
        ))
    }

    // Test destinations (local goal only)
    if goal == .local {
      entries.append(
        .init(
          keyPath: "workflows.local[test].options.destinations",
          value: nil,
          source: .unresolved,
          why:
            "Test destinations must be discovered via `xcodebuild -showdestinations` — ShipItSwifty never invents simulator names. Run the discovery command and ask the user to choose."
        ))
    }

    // Assumed defaults
    entries.append(
      .init(
        keyPath: "build.configuration",
        value: .string("Release"),
        source: .assumed,
        confidence: .high,
        why: "Release is the standard configuration for distribution"
      ))
    entries.append(
      .init(
        keyPath: "archive.export_method",
        value: .string("app-store"),
        source: .assumed,
        confidence: goal == .local ? .medium : .high,
        why: "app-store is required for TestFlight and App Store distribution"
      ))
    entries.append(
      .init(
        keyPath: "code_signing.type",
        value: .string("automatic"),
        source: .assumed,
        confidence: .medium,
        why: "Automatic signing is the lowest-friction default; switch to vault for CI environments"
      ))

    return entries
  }

  // MARK: - Ambiguities

  private func buildAmbiguities(inspection: ProjectInspection) -> [AmbiguityFlag] {
    var flags: [AmbiguityFlag] = []
    let runnableSchemes = inspection.schemes.filter(\.likelyRunnable)
    let workspaces = inspection.xcodeContainers.filter { $0.kind == "workspace" }
    let projects = inspection.xcodeContainers.filter { $0.kind == "project" }

    if runnableSchemes.count > 1 {
      flags.append(
        .init(
          field: "app.scheme",
          options: runnableSchemes.map { .string($0.name) },
          message:
            "\(runnableSchemes.count) runnable schemes found. Confirm the correct app scheme."
        ))
    }
    if !workspaces.isEmpty && !projects.isEmpty {
      flags.append(
        .init(
          field: "app.workspace / app.project",
          options: (workspaces + projects).map { .string($0.path) },
          message:
            "Both .xcworkspace and .xcodeproj files found. The workspace is preferred; confirm the correct container."
        ))
    }
    if workspaces.count > 1 {
      flags.append(
        .init(
          field: "app.workspace",
          options: workspaces.map { .string($0.path) },
          message: "\(workspaces.count) workspaces found. Confirm which one is the primary app."
        ))
    }
    return flags
  }

  // MARK: - Secrets

  private func buildSecretDescriptors(for goal: SuggestionGoal, platform: Platform)
    -> [SecretDescriptor]
  {
    switch platform {
    case .android:
      // Google Play credentials required for beta (Play Store upload) and release.
      guard goal == .beta || goal == .release else { return [] }
      return [
        SecretDescriptor(
          keyPath: "environment.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
          envVar: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
          acceptedFormats: ["File path to service account JSON", "Raw JSON string"],
          exampleSource:
            "Google Cloud Console → IAM & Admin → Service Accounts → Create Key (JSON)",
          preferFile: true,
          description:
            "Google Play service account JSON for authenticating to the Play Developer API"
        ),
        SecretDescriptor(
          keyPath: "android.keystore_password",
          envVar: "SHIPIT_ANDROID__KEYSTORE_PASSWORD",
          acceptedFormats: ["Plain text password"],
          exampleSource: "Your Android keystore file passphrase",
          preferFile: false,
          description: "Password for the Android signing keystore"
        ),
        SecretDescriptor(
          keyPath: "android.key_password",
          envVar: "SHIPIT_ANDROID__KEY_PASSWORD",
          acceptedFormats: ["Plain text password"],
          exampleSource: "Your Android signing key alias password",
          preferFile: false,
          description: "Password for the Android signing key alias within the keystore"
        ),
      ]
    case .ios:
      // ASC credentials are required for beta (TestFlight upload) and release (App Store).
      guard goal == .beta || goal == .release else { return [] }
      return [
        SecretDescriptor(
          keyPath: "app_store_connect.key_id",
          envVar: "ASC_KEY_ID",
          acceptedFormats: ["Alphanumeric string (e.g. ABCD1234EF)"],
          exampleSource:
            "App Store Connect → Users and Access → Integrations → App Store Connect API",
          preferFile: false,
          description: "The Key ID of your App Store Connect API key"
        ),
        SecretDescriptor(
          keyPath: "app_store_connect.issuer_id",
          envVar: "ASC_ISSUER_ID",
          acceptedFormats: ["UUID string (e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"],
          exampleSource:
            "App Store Connect → Users and Access → Integrations → App Store Connect API",
          preferFile: false,
          description: "The Issuer ID shown at the top of the App Store Connect API keys page"
        ),
        SecretDescriptor(
          keyPath: "app_store_connect.key_path",
          envVar: "ASC_PRIVATE_KEY_PATH",
          acceptedFormats: [
            "File path to .p8 file — use key_path in Shipfile or ASC_PRIVATE_KEY_PATH env var",
            "Raw PEM content — use private_key in Shipfile or ASC_PRIVATE_KEY env var",
          ],
          exampleSource: "Downloaded once from App Store Connect when the API key was created",
          preferFile: true,
          description:
            "The .p8 private key for your App Store Connect API key. Supply either the file path (key_path / ASC_PRIVATE_KEY_PATH) or raw content (private_key / ASC_PRIVATE_KEY)."
        ),
      ]
    }
  }

  // MARK: - Readiness

  private func buildReadiness(
    goal: SuggestionGoal,
    app: ProjectInspection.SuggestedAppConfig,
    inspection: ProjectInspection,
    requiredSecrets: [SecretDescriptor],
    platform: Platform
  ) -> AIReadiness {
    var blockers: [String] = []
    var unblockSteps: [String] = []

    switch platform {
    case .ios:
      if app.workspace == nil && app.project == nil {
        blockers.append("No Xcode workspace or project detected")
        unblockSteps.append(
          "Run shipit ai-session from the directory containing your .xcworkspace or .xcodeproj, or pass --path <dir>"
        )
      }
      if app.scheme == nil {
        blockers.append("No runnable scheme detected")
        unblockSteps.append(
          "Confirm a scheme exists in Xcode, or pass --scheme <SchemeName> and re-run")
      }
      if (goal == .beta || goal == .release) && app.bundleID == nil {
        if goal == .release {
          blockers.append(
            "Bundle ID could not be detected — required for App Store Connect API calls")
          unblockSteps.append(
            "Set app.bundle_id in Shipfile.yml or export SHIPIT_APP__BUNDLE_ID=com.example.app")
        }
      }
      // ASC credentials are only a hard blocker for release.
      if goal == .release {
        blockers.append("App Store Connect API credentials are not verified")
        unblockSteps.append(
          "Set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH (or ASC_PRIVATE_KEY) before running the workflow"
        )
      }

    case .android:
      // Android: check for gradlew or build.gradle in the project root
      if goal == .beta || goal == .release {
        blockers.append("Google Play service account credentials are not verified")
        unblockSteps.append("Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON before running the workflow")
        blockers.append("Android signing keystore credentials are not verified")
        unblockSteps.append(
          "Set SHIPIT_ANDROID__KEYSTORE_PATH, SHIPIT_ANDROID__KEYSTORE_PASSWORD, SHIPIT_ANDROID__KEY_ALIAS, SHIPIT_ANDROID__KEY_PASSWORD"
        )
      }
    }

    let signingRisk: String
    if platform == .android {
      signingRisk = "medium"
    } else if !inspection.ciFiles.isEmpty {
      signingRisk = "high"
      blockers.append("CI environment detected — Xcode automatic signing is unlikely to work in CI")
      unblockSteps.append(
        "Configure code_signing.type: vault and set up a certificates repository: shipit sign init --git-url <repo>"
      )
    } else if app.teamID != nil {
      signingRisk = "low"
    } else {
      signingRisk = "medium"
      unblockSteps.append(
        "Verify your Apple Developer Team ID is set via app.team_id or SHIPIT_APP__TEAM_ID")
    }

    return AIReadiness(
      goal: goal.rawValue,
      isReady: blockers.isEmpty,
      blockers: blockers,
      missingSecrets: requiredSecrets,
      signingRisk: signingRisk,
      unblockSteps: unblockSteps
    )
  }

  // MARK: - Next action

  private func buildNextAction(
    goal: SuggestionGoal,
    hasExistingShipfile: Bool,
    readiness: AIReadiness,
    missingValues: [SuggestedShipfile.MissingValue],
    ambiguities: [AmbiguityFlag],
    platform: Platform
  ) -> NextAction {
    let platformFlag = platform == .android ? " --platform android" : ""
    // Priority: ambiguities first, then blockers, then create/complete config, then run
    if !ambiguities.isEmpty {
      return NextAction(
        action: "resolve_ambiguity",
        reason:
          "Multiple options found for \(ambiguities.map(\.field).joined(separator: ", ")). Ask the user to confirm before generating config."
      )
    }
    if !readiness.isReady {
      let firstBlocker = readiness.blockers.first ?? "missing configuration"
      return NextAction(
        action: "resolve_blocker",
        reason: "Blocked: \(firstBlocker). Follow unblock_steps in the readiness section."
      )
    }
    if !hasExistingShipfile {
      return NextAction(
        action: "create_shipfile",
        command: "shipit generate --goal \(goal.rawValue)\(platformFlag)",
        reason:
          "No Shipfile.yml exists. Generate a starter config through the guided Shipfile generator."
      )
    }
    if !missingValues.isEmpty {
      return NextAction(
        action: "complete_config",
        command: "shipit validate yml --output json",
        reason:
          "Shipfile exists but has \(missingValues.count) unresolved field(s). Complete missing values and validate."
      )
    }
    return NextAction(
      action: "run_workflow",
      command: "shipit run \(goal.rawValue)\(platformFlag) --ci --output json",
      reason: "All required values are present. Run the workflow."
    )
  }

  // MARK: - Agent prompt

  private func buildAgentPrompt(
    goal: SuggestionGoal,
    readiness: AIReadiness,
    platform: Platform,
    customActions: [String: CustomActionConfig] = [:]
  ) -> String {
    let platformFlag = platform == .android ? " --platform android" : ""
    var lines: [String]

    switch platform {
    case .android:
      lines = [
        "You are helping an Android developer automate their app release using ShipItSwifty.",
        "Goal: \(goal.rawValue) distribution.",
        "",
        "Key commands:",
        "  shipit ai-session --goal \(goal.rawValue) --platform android  # refresh session state",
        "  shipit validate yml --output json                              # check Shipfile structure",
        "  shipit validate bundle --aab <path>                            # validate AAB before upload",
        "  shipit generate --goal \(goal.rawValue) --platform android        # generate Shipfile.yml",
        "  shipit run \(goal.rawValue)\(platformFlag) --ci --output json  # execute the workflow",
        "  shipit schema --workflow \(goal.rawValue) --output json        # schema for this goal",
        "  shipit lint --platform android                                 # run Gradle lint",
        "  shipit play-store --aab <path> --track beta                   # upload to Google Play",
        "  shipit coverage --platform android --first-party-only --targets  # summarize JaCoCo coverage",
        "",
      ]
    case .ios:
      lines = [
        "You are helping an iOS developer automate their app release using ShipItSwifty.",
        "Goal: \(goal.rawValue) distribution.",
        "",
        "Key commands:",
        "  shipit ai-session --goal \(goal.rawValue)              # refresh this session state",
        "  shipit validate yml --output json                # check Shipfile structure and semantics",
        "  shipit validate metadata --output json           # check App Store metadata (precheck)",
        "  shipit validate archive --archive-path <path>   # check xcarchive / IPA before upload",
        "  shipit validate all --output json                # run all validation stages",
        "  shipit generate --goal \(goal.rawValue)                 # generate Shipfile.yml",
        "  shipit run \(goal.rawValue) --ci --output json         # execute the workflow",
        "  shipit schema --workflow \(goal.rawValue) --output json # schema for this goal only",
        "  shipit coverage --first-party-only --targets     # summarize iOS coverage from xcresult",
        "",
      ]
    }

    if !readiness.isReady {
      lines.append(
        "Current status: NOT READY — \(readiness.blockers.count) blocker(s) must be resolved.")
      lines.append("Blockers: \(readiness.blockers.joined(separator: "; "))")
    } else {
      lines.append("Current status: READY — all required config values are present.")
    }

    switch platform {
    case .android:
      if goal == .beta {
        lines += [
          "",
          "The default Android beta workflow is: lint → test → archive (bundleRelease) → validate bundle → play-store (internal track).",
          "Google Play credentials (GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) are required for Play Store upload.",
          "Android signing requires SHIPIT_ANDROID__KEYSTORE_PATH, SHIPIT_ANDROID__KEYSTORE_PASSWORD, SHIPIT_ANDROID__KEY_ALIAS, SHIPIT_ANDROID__KEY_PASSWORD.",
          "Ask about these credentials only after the user confirms they want to upload to Google Play.",
        ]
      } else if goal == .release {
        lines += [
          "",
          "The Android release workflow targets the production track on Google Play.",
          "Staged rollout is supported via android.rollout_fraction (0.0–1.0) in Shipfile.yml.",
        ]
      }
    case .ios:
      if goal == .local {
        lines += [
          "",
          "Test destination discovery:",
          "  The local workflow includes a test step. When destinations are not configured,",
          "  ShipItSwifty auto-discovers the best iPhone simulator via `xcodebuild -showdestinations`",
          "  (highest OS version, Pro models preferred). You can still ask the user if they want to",
          "  customize destinations, but auto-discovery handles the common case automatically.",
          "  If the user wants explicit control, discover valid destinations with:",
          "    xcodebuild -showdestinations -scheme <scheme> [-workspace <ws> | -project <proj>]",
          "  Present simulators and physical devices separately. Allow multi-select.",
          "  Save the chosen destinations into workflows.local[test].options.destinations[].",
          "  If the user skips tests, remove the test step from the generated workflow.",
        ]
      }
      if goal == .beta {
        lines += [
          "",
          "Versioning (Apple two-version model):",
          "  CFBundleShortVersionString — MAJOR.MINOR.PATCH marketing version. Never changed during beta runs.",
          "  CFBundleVersion            — plain integer build counter. Incremented by `version` action with bump: build.",
          "  versioning.strategy: sequential  (guarantees CFBundleVersion stays a plain integer)",
          "  versioning.source: xcodeproj     (reads/writes Xcode build settings directly)",
          "",
          "  For XcodeGen / spec-driven projects where .xcodeproj is generated:",
          "    versioning.source: project_spec  (reads/writes version values directly in the spec YAML file)",
          "    versioning.spec_path: project.yml  (or auto-discovered from project_generation.spec_path)",
          "    versioning.build_key / marketing_key can be customised if the project uses non-standard setting names.",
          "    The `version` action accepts a `target: source_of_truth` option to override the config source per-step.",
          "",
          "Project generation (XcodeGen / Tuist / other spec-driven tools):",
          "  When project_generation.tool is set in Shipfile.yml, ShipItSwifty auto-generates the .xcodeproj",
          "  before any Xcode-dependent workflow step (build, test, archive, etc.).",
          "  project_generation.auto_generate: true (default) — skip generation when the output already exists.",
          "  Use `generate_project` action explicitly to force regeneration.",
          "",
          "Test destination auto-discovery:",
          "  When no `destinations` are configured for the test step, ShipItSwifty auto-discovers",
          "  available iPhone simulators via `xcodebuild -showdestinations` and selects the best one",
          "  (highest OS version, preferring Pro models). This eliminates manual simulator configuration",
          "  for most projects.",
          "",
          "The default beta workflow is LOCAL-ONLY: version → archive → export.",
          "App Store Connect credentials are NOT required for local-only beta.",
          "Only ask about ASC credentials (ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH) after",
          "the user confirms they want to upload to TestFlight.",
        ]
      } else if goal == .release {
        lines += [
          "",
          "Versioning (Apple two-version model):",
          "  CFBundleShortVersionString — MAJOR.MINOR.PATCH. Bump with `version` + bump: patch/minor/major.",
          "  CFBundleVersion            — plain integer. Reset to 1 when marketing version is bumped.",
          "",
          "  For XcodeGen / spec-driven projects, use versioning.source: project_spec",
          "  or the `target: source_of_truth` option on the version step to write to the spec file.",
        ]
      }
    }

    if !readiness.missingSecrets.isEmpty {
      lines += [
        "",
        "Required secrets (never ask the user for actual values — only ask if each is set):",
      ]
      for secret in readiness.missingSecrets {
        lines.append("  \(secret.envVar): \(secret.description)")
      }
    }
    lines += [
      "",
      "When config is incomplete, ask one focused question at a time, starting with the highest-impact missing value.",
    ]

    // Custom composite actions are first-class. Always mention the feature;
    // enumerate concrete ones when the resolved Shipfile defines any.
    lines += [
      "",
      "Custom actions:",
      "  Users can define reusable step sequences under `custom_actions:` in Shipfile.yml to avoid duplicating",
      "  step blocks across workflows (for example sharing `test → archive → export` between beta and ad-hoc).",
      "  Call them from workflow steps the same way as built-ins (`action: <name>` + optional `options:`).",
      "  Inside a composite's step options, reference declared parameters as `{{param.NAME}}` — this syntax",
      "  is chosen specifically to avoid collisions with Shipfile's `${ENV_VAR}` expansion, GitHub Actions",
      "  `${{ ... }}`, and CircleCI `<< ... >>` templating, so it is safe to use in any CI environment.",
    ]
    if !customActions.isEmpty {
      lines.append("  Defined in this project:")
      for (name, config) in customActions.sorted(by: { $0.key < $1.key }) {
        let params = (config.parameters ?? [:]).keys.sorted().joined(separator: ", ")
        let paramSuffix = params.isEmpty ? "" : "  (params: \(params))"
        let desc = config.description.map { " — \($0)" } ?? ""
        lines.append("    - \(name)\(paramSuffix)\(desc)")
      }
      lines.append(
        "  Prefer invoking an existing custom action over duplicating its step sequence in a new workflow."
      )
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Next question

  private func buildNextQuestion(
    goal: SuggestionGoal,
    missingValues: [SuggestedShipfile.MissingValue],
    ambiguities: [AmbiguityFlag],
    readiness: AIReadiness,
    platform: Platform
  ) -> String? {
    // Ambiguities first — must be resolved before config can be generated
    if let first = ambiguities.first {
      let opts = first.options.compactMap(\.stringValue).joined(separator: ", ")
      return "\(first.message) Options: \(opts)"
    }

    switch platform {
    case .android:
      // For Android, ask about Google Play credentials for beta/release
      if (goal == .beta || goal == .release) && !readiness.missingSecrets.isEmpty {
        return
          "Do you have your Google Play service account JSON ready? You'll need: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON, SHIPIT_ANDROID__KEYSTORE_PATH, SHIPIT_ANDROID__KEYSTORE_PASSWORD, SHIPIT_ANDROID__KEY_ALIAS, SHIPIT_ANDROID__KEY_PASSWORD."
      }
      // Check for remaining missing config values
      if let first = missingValues.first {
        let envSuffix = first.envVar.map { " (or set \($0))" } ?? ""
        return "What is the value for \(first.keyPath)? Reason: \(first.reason)\(envSuffix)"
      }
      if goal == .beta {
        return
          "The Android beta workflow will build a release AAB and upload to the internal track on Google Play. Do you want to target a different track (alpha, beta, production)?"
      }

    case .ios:
      // For release, ASC secrets are a hard blocker — ask immediately.
      if goal == .release && !readiness.missingSecrets.isEmpty {
        return
          "Do you have your App Store Connect API credentials ready? You'll need: ASC_KEY_ID, ASC_ISSUER_ID, and either ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH."
      }
      // For local goal, the test step requires destinations — ask about it first.
      if goal == .local,
        let testDestMissing = missingValues.first(where: { $0.keyPath.contains("destinations") })
      {
        _ = testDestMissing
        return """
          This workflow includes a test step. Do you want to run tests? \
          If yes, I can discover available simulators and devices for your scheme using \
          `xcodebuild -showdestinations`. Would you like me to list them so you can choose \
          which ones to run tests on? (simulators, physical devices, or a mix)
          """
      }
      // Unresolved required config values (skip the test destinations one — already asked above)
      if let first = missingValues.first(where: { !$0.keyPath.contains("destinations") }) {
        let envSuffix = first.envVar.map { " (or set \($0))" } ?? ""
        return "What is the value for \(first.keyPath)? Reason: \(first.reason)\(envSuffix)"
      }
      // Beta: once config is complete, ask about TestFlight upload intent
      if goal == .beta {
        return
          "The beta workflow will build and export the .ipa locally. Do you also want to upload to TestFlight? If yes, I'll add the App Store Connect credentials and a testflight step."
      }
    }

    return nil
  }
}

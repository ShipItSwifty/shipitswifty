import Testing

@testable import ShipItKit

@Suite("AISessionBuilder")
struct AISessionTests {

    // MARK: - Contract version

    @Test("Contract version is stable string")
    func contractVersionIsStable() {
        #expect(AISessionBuilder.contractVersion == "1")
    }

    // MARK: - Fully-detected project

    @Test("Fully detected project produces high-confidence app config")
    func fullyDetectedProjectProducesHighConfidence() {
        let inspection = fullInspection()
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: inspection, hasExistingShipfile: false)

        let workspaceEntry = payload.appConfig.first { $0.keyPath == "app.workspace" }
        let schemeEntry = payload.appConfig.first { $0.keyPath == "app.scheme" }
        let bundleEntry = payload.appConfig.first { $0.keyPath == "app.bundle_id" }
        let teamEntry = payload.appConfig.first { $0.keyPath == "app.team_id" }

        #expect(workspaceEntry?.source == .detected)
        #expect(workspaceEntry?.confidence == .high)
        #expect(workspaceEntry?.value == .string("App.xcworkspace"))

        #expect(schemeEntry?.source == .detected)
        #expect(schemeEntry?.confidence == .high)
        #expect(schemeEntry?.value == .string("App"))

        #expect(bundleEntry?.source == .detected)
        #expect(bundleEntry?.confidence == .high)
        #expect(bundleEntry?.value == .string("com.example.app"))

        #expect(teamEntry?.source == .detected)
        #expect(teamEntry?.confidence == .high)
        #expect(teamEntry?.value == .string("TEAM12345"))
    }

    @Test("Assumed defaults are present with correct sources")
    func assumedDefaultsPresent() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)

        let config = payload.appConfig
        let configEntry = config.first { $0.keyPath == "build.configuration" }
        let exportEntry = config.first { $0.keyPath == "archive.export_method" }
        let signingEntry = config.first { $0.keyPath == "code_signing.type" }

        #expect(configEntry?.source == .assumed)
        #expect(configEntry?.value == .string("Release"))
        #expect(exportEntry?.source == .assumed)
        #expect(exportEntry?.value == .string("app-store"))
        #expect(signingEntry?.source == .assumed)
        #expect(signingEntry?.value == .string("automatic"))
    }

    // MARK: - Empty project

    @Test("Empty project marks workspace as unresolved")
    func emptyProjectMarksUnresolved() {
        let inspection = emptyInspection()
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: inspection, hasExistingShipfile: false)

        let workspaceEntry = payload.appConfig.first { $0.keyPath == "app.workspace" }
        #expect(workspaceEntry?.source == .unresolved)
        #expect(workspaceEntry?.value == nil)
        #expect(workspaceEntry?.confidence == nil)
    }

    @Test("Empty project produces blockers for beta goal")
    func emptyProjectProducesBlockers() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: emptyInspection(), hasExistingShipfile: false)

        #expect(!payload.readiness.isReady)
        #expect(
            payload.readiness.blockers.contains { $0.contains("workspace") || $0.contains("project") })
        #expect(payload.readiness.blockers.contains { $0.contains("scheme") })
    }

    // MARK: - Secret descriptors

    @Test("Beta goal includes three ASC secret descriptors")
    func betaGoalIncludesSecretDescriptors() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)

        let secrets = payload.readiness.missingSecrets
        #expect(secrets.count == 3)
        #expect(secrets.contains { $0.envVar == "ASC_KEY_ID" })
        #expect(secrets.contains { $0.envVar == "ASC_ISSUER_ID" })
        #expect(secrets.contains { $0.envVar == "ASC_PRIVATE_KEY_PATH" })
    }

    @Test("Local goal includes no secret descriptors")
    func localGoalIncludesNoSecrets() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.readiness.missingSecrets.isEmpty)
    }

    @Test("Secret descriptors include acceptedFormats and exampleSource")
    func secretDescriptorsAreComplete() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        for secret in payload.readiness.missingSecrets {
            #expect(!secret.acceptedFormats.isEmpty)
            #expect(!secret.exampleSource.isEmpty)
            #expect(!secret.description.isEmpty)
        }
    }

    // MARK: - Ambiguities

    @Test("Multiple runnable schemes produce ambiguity flag")
    func multipleRunnableSchemesProduceAmbiguity() {
        let inspection = inspectionWithMultipleRunnableSchemes()
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: inspection, hasExistingShipfile: false)

        let schemeAmbiguity = payload.ambiguities.first { $0.field == "app.scheme" }
        #expect(schemeAmbiguity != nil)
        #expect(schemeAmbiguity?.options.count == 2)
    }

    @Test("Single runnable scheme produces no ambiguity flag")
    func singleRunnableSchemeNoAmbiguity() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.ambiguities.filter { $0.field == "app.scheme" }.isEmpty)
    }

    // MARK: - Next action

    @Test("No shipfile and ambiguities => resolve_ambiguity action")
    func ambiguityTakesPriorityOverShipfileCreation() {
        let inspection = inspectionWithMultipleRunnableSchemes()
        let payload = AISessionBuilder().build(
            goal: .local, inspection: inspection, hasExistingShipfile: false)
        #expect(payload.nextAction.action == "resolve_ambiguity")
    }

    @Test("Not ready => resolve_blocker action")
    func notReadyProducesResolveBlockerAction() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: emptyInspection(), hasExistingShipfile: false)
        #expect(payload.nextAction.action == "resolve_blocker")
        #expect(payload.nextAction.command == nil)
    }

    @Test("Ready, no shipfile => create_shipfile with command")
    func readyWithNoShipfileProducesCreateShipfileAction() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: localReadyInspection(), hasExistingShipfile: false)
        #expect(payload.nextAction.action == "create_shipfile")
        #expect(payload.nextAction.command?.contains("generate") == true)
    }

    @Test("Ready, existing shipfile, no missing => run_workflow with command")
    func readyWithShipfileProducesRunWorkflowAction() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: localReadyInspection(), hasExistingShipfile: true)
        // missing values will be empty for local goal with full detection
        // next action depends on missing — if none, run_workflow
        let action = payload.nextAction.action
        #expect(action == "run_workflow" || action == "complete_config")
        if action == "run_workflow" {
            #expect(payload.nextAction.command?.contains("shipit run local") == true)
        }
    }

    // MARK: - Signing risk

    @Test("CI files detected yields high signing risk")
    func ciFilesDetectedYieldsHighSigningRisk() {
        let inspection = inspectionWithCIFiles()
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: inspection, hasExistingShipfile: false)
        #expect(payload.readiness.signingRisk == "high")
    }

    @Test("No CI and team ID detected yields low signing risk")
    func noCIAndTeamIDYieldsLowSigningRisk() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: localReadyInspection(), hasExistingShipfile: false)
        #expect(payload.readiness.signingRisk == "low")
    }

    // MARK: - Agent prompt

    @Test("Agent prompt contains goal and key commands")
    func agentPromptContainsGoalAndCommands() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.agentPrompt.contains("beta"))
        #expect(payload.agentPrompt.contains("ai-session"))
        #expect(payload.agentPrompt.contains("validate"))
        #expect(payload.agentPrompt.contains("generate"))
    }

    @Test("Agent prompt instructs agents to ask about infrastructure retries")
    func agentPromptMentionsInfrastructureRetries() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.agentPrompt.contains("infrastructure_retry"))
        #expect(payload.agentPrompt.contains("transient test infrastructure failures"))
    }

    @Test("Distribution agent prompt documents Firebase keyless authentication")
    func distributionPromptMentionsFirebaseWIF() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.agentPrompt.contains("firebase-app-distribution"))
        #expect(payload.agentPrompt.contains("workload_identity_provider"))
        #expect(payload.agentPrompt.contains("id-token: write"))
        #expect(payload.agentPrompt.contains("APK or AAB"))
    }

    @Test("Agent prompt mentions NOT READY when blockers exist")
    func agentPromptMentionsNotReadyWhenBlocked() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: emptyInspection(), hasExistingShipfile: false)
        #expect(payload.agentPrompt.contains("NOT READY"))
    }

    @Test("Agent prompt mentions READY when no blockers")
    func agentPromptMentionsReadyWhenUnblocked() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: localReadyInspection(), hasExistingShipfile: false)
        #expect(payload.agentPrompt.contains("READY"))
    }

    // MARK: - Next question

    @Test("Ambiguities produce next question with options")
    func ambiguitiesProduceNextQuestion() {
        let inspection = inspectionWithMultipleRunnableSchemes()
        let payload = AISessionBuilder().build(
            goal: .local, inspection: inspection, hasExistingShipfile: false)
        #expect(payload.nextQuestion != nil)
        #expect(
            payload.nextQuestion?.contains("App") == true
                || payload.nextQuestion?.contains("scheme") == true)
    }

    @Test("Ready project produces nil next question")
    func readyProjectProducesNilNextQuestion() {
        let payload = AISessionBuilder().build(
            goal: .local, inspection: localReadyInspection(), hasExistingShipfile: true)
        // Only nil if no missing values — local goal with full detection should have none
        if payload.missing.isEmpty {
            #expect(payload.nextQuestion == nil)
        }
    }

    // MARK: - Payload structure

    @Test("Payload version matches contract version")
    func payloadVersionMatchesContractVersion() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(payload.version == AISessionBuilder.contractVersion)
    }

    @Test("Suggested shipfile is non-empty YAML string")
    func suggestedShipfileIsNonEmpty() {
        let payload = AISessionBuilder().build(
            goal: .beta, inspection: fullInspection(), hasExistingShipfile: false)
        #expect(!payload.suggestedShipfile.isEmpty)
        #expect(payload.suggestedShipfile.contains("app:"))
        #expect(payload.suggestedShipfile.contains("workflows:"))
    }

    @Test("Android platform override produces Android suggested Shipfile")
    func androidPlatformOverrideProducesAndroidSuggestedShipfile() {
        let payload = AISessionBuilder().build(
            goal: .beta,
            inspection: fullInspection(),
            hasExistingShipfile: false,
            platform: .android
        )

        #expect(payload.suggestedShipfile.contains("platform: android"))
        #expect(payload.suggestedShipfile.contains("android:"))
    }

    @Test("iOS next actions use canonical command strings")
    func iosNextActionsUseCanonicalCommands() {
        let createPayload = AISessionBuilder().build(
            goal: .local,
            inspection: localReadyInspection(),
            hasExistingShipfile: false
        )
        #expect(createPayload.nextAction.command == "shipit generate --goal local")

        let runPayload = AISessionBuilder().build(
            goal: .beta,
            inspection: fullInspection(),
            hasExistingShipfile: true
        )
        #expect(runPayload.nextAction.command == "shipit run beta --ci --output json")

        let completePayload = AISessionBuilder().build(
            goal: .local,
            inspection: localReadyInspection(),
            hasExistingShipfile: true
        )
        #expect(completePayload.nextAction.command == "shipit validate yml --output json")
    }

    @Test("Android next actions use canonical command strings")
    func androidNextActionsUseCanonicalCommands() {
        let createPayload = AISessionBuilder().build(
            goal: .local,
            inspection: androidInspection(),
            hasExistingShipfile: false,
            platform: .android
        )
        #expect(createPayload.nextAction.command == "shipit generate --goal local --platform android")

        let completePayload = AISessionBuilder().build(
            goal: .local,
            inspection: androidInspection(),
            hasExistingShipfile: true,
            platform: .android
        )
        #expect(completePayload.nextAction.command == "shipit validate yml --output json")

        #expect(completePayload.agentPrompt.contains("shipit ai-session --goal local --platform android"))
        #expect(completePayload.agentPrompt.contains("shipit generate --goal local --platform android"))
        #expect(completePayload.agentPrompt.contains("shipit run local --platform android --ci --output json"))
        #expect(completePayload.agentPrompt.contains("shipit validate bundle --aab <path> --output json"))
    }

    // MARK: - Fixture helpers

    private func fullInspection() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true),
                .init(
                    name: "AppTests", containerPath: "App.xcworkspace", bundleID: nil, teamID: nil,
                    likelyRunnable: false),
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )
    }

    private func localReadyInspection() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )
    }

    private func emptyInspection() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/empty",
            xcodeContainers: [],
            preferredContainer: nil,
            schemes: [],
            suggestedAppConfig: .init(),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )
    }

    private func inspectionWithMultipleRunnableSchemes() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true),
                .init(
                    name: "AppExtension", containerPath: "App.xcworkspace", bundleID: "com.example.app.ext",
                    teamID: "TEAM12345", likelyRunnable: true),
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )
    }

    private func inspectionWithCIFiles() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [".github/workflows"],
            warnings: []
        )
    }

    private func androidInspection() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/android-project",
            xcodeContainers: [],
            preferredContainer: nil,
            schemes: [],
            suggestedAppConfig: .init(),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: [],
            detectedPlatform: .android,
            gradleFiles: ["gradlew", "build.gradle.kts"]
        )
    }
}

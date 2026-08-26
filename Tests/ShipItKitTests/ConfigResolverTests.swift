import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ConfigResolver")
struct ConfigResolverTests {

    @Test("Shipfile overrides environment values")
    func shipfileOverridesEnvironment() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          workspace: Example.xcworkspace
          scheme: ShipfileScheme
          bundle_id: com.example.shipfile
        build:
          configuration: Debug
        app_store_connect:
          key_id: ShipfileKey
          issuer_id: ShipfileIssuer
        versioning:
          strategy: sequential
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_APP__WORKSPACE": "Env.xcworkspace",
            "SHIPIT_APP__SCHEME": "EnvScheme",
            "SHIPIT_APP__BUNDLE_ID": "com.example.env",
            "SHIPIT_APP__TEAM_ID": "ENVTEAM123",
            "SHIPIT_BUILD__CONFIGURATION": "Release",
            "ASC_KEY_ID": "EnvKey",
            "ASC_ISSUER_ID": "EnvIssuer",
        ])
        let resolver = ConfigResolver(environment: environment)

        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        // Shipfile values win when both sources provide a value
        #expect(config.appScheme == "ShipfileScheme")
        #expect(config.appWorkspace == tempDirectory.appendingPathComponent("Example.xcworkspace").path)
        #expect(config.bundleID == "com.example.shipfile")
        #expect(config.buildConfiguration == "Debug")
        #expect(config.ascKeyID == "ShipfileKey")
        #expect(config.ascIssuerID == "ShipfileIssuer")
        // Env is used as fallback when Shipfile doesn't provide the value
        #expect(config.teamID == "ENVTEAM123")
    }

    @Test("Relative paths resolve from the Shipfile directory")
    func relativePathsResolveFromShipfileDirectory() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        app:
          project: ios/App.xcodeproj
        build:
          derived_data_path: build/DerivedData
        archive:
          output_path: build/App.xcarchive
        export:
          archive_path: build/App.xcarchive
          output_directory: build/export
        versioning:
          source: project_spec
          spec_path: config/project.yml
        project_generation:
          tool: xcodegen
          spec_path: config/project.yml
          output_project: ios/App.xcodeproj
        android:
          gradlew_path: android/gradlew
          gradle_project_dir: android
          keystore_path: signing/release.jks
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        #expect(config.appProject == tempDirectory.appendingPathComponent("ios/App.xcodeproj").path)
        #expect(config.derivedDataPath == tempDirectory.appendingPathComponent("build/DerivedData").path)
        #expect(config.archiveOutputPath == tempDirectory.appendingPathComponent("build/App.xcarchive").path)
        #expect(config.exportOutputDirectory == tempDirectory.appendingPathComponent("build/export").path)
        #expect(config.versioningSpecPath == tempDirectory.appendingPathComponent("config/project.yml").path)
        #expect(config.projectGenerationOutputProject == tempDirectory.appendingPathComponent("ios/App.xcodeproj").path)
        #expect(config.gradlewPath == tempDirectory.appendingPathComponent("android/gradlew").path)
        #expect(config.gradleProjectDir == tempDirectory.appendingPathComponent("android").path)
        #expect(config.androidKeystorePath == tempDirectory.appendingPathComponent("signing/release.jks").path)
    }

    @Test("CLI overrides environment and shipfile values")
    func cliOverridesEnvironment() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: ShipfileScheme
        build:
          configuration: Debug
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_APP__SCHEME": "EnvScheme",
            "SHIPIT_BUILD__CONFIGURATION": "Release",
        ])
        let resolver = ConfigResolver(environment: environment)

        let config = try await resolver.resolve(
            cliOptions: CLIOptions(scheme: "CLIScheme", configuration: "Profile"),
            shipfilePath: shipfileURL.path
        )

        #expect(config.appScheme == "CLIScheme")
        #expect(config.buildConfiguration == "Profile")
    }

    @Test("Platform resolves from Shipfile when no higher-priority override exists")
    func platformResolvesFromShipfile() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        android:
          module: app
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.platform == .android)
    }

    @Test("CLI platform overrides Shipfile platform")
    func cliPlatformOverridesShipfilePlatform() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        android:
          module: app
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(
            cliOptions: CLIOptions(platform: .ios),
            shipfilePath: shipfileURL.path
        )

        #expect(config.platform == .ios)
    }

    @Test("Android task scope and test emulators resolve from Shipfile")
    func androidTaskScopeAndTestEmulatorsResolveFromShipfile() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        android:
          module: app
          scope: root
          test_kind: instrumented
          test_devices:
            strategy: named_emulators
            emulators:
              - Pixel_9_API_35
              - Pixel_Tablet_API_35
            prompt_locally: true
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.platform == .android)
        #expect(config.androidScope == .root)
        #expect(config.androidTestKind == .instrumented)
        #expect(config.androidTestDevices.strategy == .namedEmulators)
        #expect(config.androidTestDevices.emulators == ["Pixel_9_API_35", "Pixel_Tablet_API_35"])
        #expect(config.androidTestDevices.promptLocally == true)
    }

    @Test("Android flavor resolves into Gradle properties")
    func androidFlavorResolvesIntoGradleProperties() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        android:
          module: app
          build_variant: release
          flavor: prod
          gradle_properties:
            ci: "true"
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.androidGradleProperties["flavor"] == "prod")
        #expect(config.androidGradleProperties["ci"] == "true")
    }

    @Test("CLI CI flag resolves into config")
    func ciFlagResolvesIntoConfig() async throws {
        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(cliOptions: CLIOptions(ci: true), shipfilePath: "/tmp/does-not-exist.yml")

        #expect(config.ci)
    }

    @Test("CLI scheme override preserves workspace resolution")
    func cliSchemePreservesWorkspace() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          workspace: Example.xcworkspace
          scheme: ShipfileScheme
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())

        let config = try await resolver.resolve(
            cliOptions: CLIOptions(scheme: "CLIScheme"),
            shipfilePath: shipfileURL.path
        )

        #expect(config.appScheme == "CLIScheme")
        #expect(config.appWorkspace == tempDirectory.appendingPathComponent("Example.xcworkspace").path)
    }

    @Test("Raw ASC private key environment is loaded")
    func privateKeyFromEnvironment() async throws {
        let resolver = ConfigResolver(
            environment: Environment(env: [
                "ASC_PRIVATE_KEY": "PRIVATE-KEY-DATA"
            ]))

        let config = try await resolver.resolve(shipfilePath: "/tmp/does-not-exist.yml")

        #expect(config.ascPrivateKeyData == Data("PRIVATE-KEY-DATA".utf8))
    }

    @Test("Shipfile raw ASC private key is loaded")
    func privateKeyFromShipfile() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        app_store_connect:
          key_id: KEY
          issuer_id: ISSUER
          private_key: PRIVATE-KEY-DATA
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.ascPrivateKeyData == Data("PRIVATE-KEY-DATA".utf8))
    }

    @Test("Processed files include Shipfile and ASC key file")
    func processedFilesIncludeLoadedConfigFiles() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKeyURL = tempDirectory.appendingPathComponent("AuthKey_TEST.p8")
        try "PRIVATE-KEY-DATA".write(to: privateKeyURL, atomically: true, encoding: .utf8)

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        app_store_connect:
          key_id: KEY
          issuer_id: ISSUER
          key_path: \(privateKeyURL.path)
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.processedFiles == [shipfileURL.path, privateKeyURL.path])
    }

    @Test("Processed files stay empty when no files are loaded")
    func processedFilesEmptyWhenNoFilesLoaded() async throws {
        let resolver = ConfigResolver(
            environment: Environment(env: [
                "ASC_PRIVATE_KEY": "PRIVATE-KEY-DATA"
            ]))

        let config = try await resolver.resolve(shipfilePath: "/tmp/does-not-exist.yml")

        #expect(config.processedFiles.isEmpty)
    }

    #if os(macOS)
    @Test("Bundle ID and team ID are inferred from Xcode build settings")
    func infersBundleIDAndTeamIDFromBuildSettings() async throws {
        let executor = MockExecutor { command, _ in
            #expect(command.executableName == "xcodebuild")
            #expect(command.arguments.contains("-showBuildSettings"))
            return ShellOutput(
                stdout: """
                    Build settings for action build and target Example:\n
                        PRODUCT_BUNDLE_IDENTIFIER = com.example.detected\n
                        DEVELOPMENT_TEAM = DETECTTEAM\n
                    """,
                stderr: "",
                exitCode: 0
            )
        }

        let resolver = ConfigResolver(
            environment: Environment(),
            shell: ShellContext(executor: executor)
        )

        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.bundleID == "com.example.detected")
        #expect(config.bundleIDFromTargetBuildSettings)
        #expect(config.teamID == "DETECTTEAM")
        #expect(config.teamIDFromTargetBuildSettings)
    }
    #endif

    @Test("Automatic code signing flag resolves from Shipfile")
    func automaticCodeSigningFromShipfile() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        code_signing:
          type: automatic
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.codeSigningType == "automatic")
        #expect(config.automaticCodeSigning)
    }

    @Test("Manual signing paths are preferred over base64 fallbacks")
    func manualSigningPathsPreferredOverBase64() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let p12URL = tempDirectory.appendingPathComponent("distribution.p12")
        let profileURL = tempDirectory.appendingPathComponent("AppStore.mobileprovision")
        try Data("local-p12".utf8).write(to: p12URL)
        try Data("local-profile".utf8).write(to: profileURL)

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        code_signing:
          type: manual
          p12_path: \(p12URL.path)
          p12_base64: \(Data("ci-p12".utf8).base64EncodedString())
          p12_password: local-password
          provisioning_profile_path: \(profileURL.path)
          provisioning_profile_base64: \(Data("ci-profile".utf8).base64EncodedString())
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        #expect(config.codeSigningType == "manual")
        #expect(config.codeSigningP12Path == p12URL.path)
        #expect(config.codeSigningP12Data == nil)
        #expect(config.codeSigningP12Password == "local-password")
        #expect(config.codeSigningProvisioningProfilePath == profileURL.path)
        #expect(config.codeSigningProvisioningProfileData == nil)
    }

    @Test("Manual signing falls back to base64 when paths are missing")
    func manualSigningFallsBackToBase64() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
        code_signing:
          type: manual
          p12_path: \(tempDirectory.appendingPathComponent("missing.p12").path)
          provisioning_profile_path: \(tempDirectory.appendingPathComponent("missing.mobileprovision").path)
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "P12_BASE64": Data("ci-p12".utf8).base64EncodedString(),
            "P12_PASSWORD": "ci-password",
            "PROVISIONING_PROFILE_BASE64": Data("ci-profile".utf8).base64EncodedString(),
        ])

        let config = try await ConfigResolver(environment: environment).resolve(shipfilePath: shipfileURL.path)

        #expect(config.codeSigningP12Path == nil)
        #expect(config.codeSigningP12Data == Data("ci-p12".utf8))
        #expect(config.codeSigningP12Password == "ci-password")
        #expect(config.codeSigningProvisioningProfilePath == nil)
        #expect(config.codeSigningProvisioningProfileData == Data("ci-profile".utf8))
    }

    @Test("Invalid manual signing base64 throws invalid configuration")
    func invalidManualSigningBase64Throws() async throws {
        let resolver = ConfigResolver(
            environment: Environment(env: [
                "P12_BASE64": "not-valid-base64"
            ]))

        await #expect {
            _ = try await resolver.resolve(shipfilePath: "/tmp/does-not-exist.yml")
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("base64")
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Project generation config

    @Test("Resolves project generation config from Shipfile")
    func resolvesProjectGenerationConfig() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: MyApp.xcodeproj
          scheme: MyApp
        project_generation:
          tool: xcodegen
          command: xcodegen generate --spec custom.yml
          spec_path: custom.yml
          output_project: MyApp.xcodeproj
          auto_generate: false
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.projectGenerationTool == "xcodegen")
        #expect(config.projectGenerationCommand == "xcodegen generate --spec custom.yml")
        #expect(config.projectGenerationSpecPath == tempDirectory.appendingPathComponent("custom.yml").path)
        #expect(config.projectGenerationOutputProject == tempDirectory.appendingPathComponent("MyApp.xcodeproj").path)
        #expect(config.projectGenerationAutoGenerate == false)
    }

    @Test("Project generation defaults auto_generate to true when not specified")
    func projectGenerationDefaultsAutoGenerate() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        project_generation:
          tool: xcodegen
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.projectGenerationTool == "xcodegen")
        #expect(config.projectGenerationAutoGenerate == true)
    }

    @Test("Default project generation command is derived from tool name")
    func defaultProjectGenerationCommandFromTool() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        project_generation:
          tool: xcodegen
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        // Should auto-derive "xcodegen generate" from tool name
        #expect(config.projectGenerationCommand == "xcodegen generate")
    }

    @Test("versioning.spec_path falls back to project_generation.spec_path")
    func versioningSpecPathFallsBack() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        project_generation:
          tool: xcodegen
          spec_path: project.yml
        versioning:
          source: project_spec
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.versioningSource == "project_spec")
        #expect(config.versioningSpecPath == tempDirectory.appendingPathComponent("project.yml").path)
    }

    @Test("Explicit versioning.spec_path overrides project_generation.spec_path")
    func explicitVersioningSpecPathOverrides() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        project_generation:
          tool: xcodegen
          spec_path: project.yml
        versioning:
          source: project_spec
          spec_path: custom-version-spec.yml
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.versioningSpecPath == tempDirectory.appendingPathComponent("custom-version-spec.yml").path)
        #expect(config.projectGenerationSpecPath == tempDirectory.appendingPathComponent("project.yml").path)
    }

    @Test("Versioning custom build_key and marketing_key are resolved")
    func versioningCustomKeysResolved() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        versioning:
          source: project_spec
          build_key: MY_BUILD_NUMBER
          marketing_key: MY_VERSION_STRING
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.versioningBuildKey == "MY_BUILD_NUMBER")
        #expect(config.versioningMarketingKey == "MY_VERSION_STRING")
    }

    @Test("Versioning keys default to standard Xcode names")
    func versioningKeysDefaults() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.versioningBuildKey == "CURRENT_PROJECT_VERSION")
        #expect(config.versioningMarketingKey == "MARKETING_VERSION")
    }

    @Test("No project generation config when block is absent")
    func noProjectGenerationWhenAbsent() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment())
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.projectGenerationTool == nil)
        #expect(config.projectGenerationCommand == nil)
        #expect(config.projectGenerationSpecPath == nil)
        #expect(config.projectGenerationOutputProject == nil)
        #expect(config.projectGenerationAutoGenerate == true)
    }

    // MARK: - ${ENV_VAR} expansion

    @Test("Expands ${ENV_VAR} references against the process environment")
    func expandsDefinedEnvironmentVariable() async throws {
        // Uniquely-named var avoids collisions under parallel test execution.
        let varName = "SHIPIT_TEST_EXPAND_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        setenv(varName, "ExpandedScheme", 1)
        defer { unsetenv(varName) }

        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: ${\(varName)}
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        #expect(config.appScheme == "ExpandedScheme")
    }

    @Test("Leaves undefined ${ENV_VAR} references untouched")
    func leavesUndefinedEnvironmentVariableLiteral() async throws {
        let varName = "SHIPIT_TEST_UNDEFINED_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        // Deliberately NOT set in the environment.

        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: ${\(varName)}
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        // Unresolved references are preserved verbatim (and logged as a warning),
        // never silently collapsed to an empty string.
        #expect(config.appScheme == "${\(varName)}")
    }

    @Test("AndroidCLI is disabled by default and resolves explicit Shipfile settings")
    func androidCLIConfiguration() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        platform: android
        android:
          cli:
            enabled: true
            executable_path: tools/android
            sdk_path: sdk
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)
        #expect(config.androidCLI.enabled == true)
        #expect(config.androidCLI.executablePath == tempDirectory.appendingPathComponent("tools/android").path)
        #expect(config.androidCLI.sdkPath == tempDirectory.appendingPathComponent("sdk").path)

        let defaults = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: tempDirectory.appendingPathComponent("Missing.yml").path)
        #expect(defaults.androidCLI.enabled == false)
        #expect(defaults.androidCLI.executablePath == "android")
    }
}

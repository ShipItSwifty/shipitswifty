import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ConfigResolver")
struct ConfigResolverTests {

  @Test("Environment overrides shipfile values")
  func environmentOverridesShipfile() async throws {
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
    versioning:
      strategy: sequential
    """.write(to: shipfileURL, atomically: true, encoding: .utf8)

    let environment = Environment(env: [
      "SHIPIT_APP__WORKSPACE": "Env.xcworkspace",
      "SHIPIT_APP__SCHEME": "EnvScheme",
      "SHIPIT_APP__BUNDLE_ID": "com.example.env",
      "SHIPIT_APP__TEAM_ID": "ENVTEAM123",
      "SHIPIT_BUILD__CONFIGURATION": "Release",
      "ASC_KEY_ID": "ENVKEY",
      "ASC_ISSUER_ID": "ENVISSUER",
    ])
    let resolver = ConfigResolver(environment: environment)

    let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

    #expect(config.appScheme == "EnvScheme")
    #expect(config.appWorkspace == "Env.xcworkspace")
    #expect(config.bundleID == "com.example.env")
    #expect(config.teamID == "ENVTEAM123")
    #expect(config.buildConfiguration == "Release")
    #expect(config.ascKeyID == "ENVKEY")
    #expect(config.ascIssuerID == "ENVISSUER")
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
    #expect(config.appWorkspace == "Example.xcworkspace")
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
    #expect(config.projectGenerationSpecPath == "custom.yml")
    #expect(config.projectGenerationOutputProject == "MyApp.xcodeproj")
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
    #expect(config.versioningSpecPath == "project.yml")
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

    #expect(config.versioningSpecPath == "custom-version-spec.yml")
    #expect(config.projectGenerationSpecPath == "project.yml")
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
}

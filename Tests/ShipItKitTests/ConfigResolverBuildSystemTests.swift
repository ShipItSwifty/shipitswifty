import Foundation
import Testing

@testable import ShipItKit

@Suite("ConfigResolver — BuildSystem resolution")
struct ConfigResolverBuildSystemTests {

    @Test("Defaults to .native when no source sets a build system")
    func defaultsToNative() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .native)
        #expect(config.androidBuildSystem == .native)
    }

    @Test("Reads build_system from the ios: block")
    func readsIOSShipfileBlock() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        ios:
          build_system: kmp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .kmp)
        #expect(config.androidBuildSystem == .native)
    }

    @Test("Reads build_system from the android: block")
    func readsAndroidShipfileBlock() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        android:
          module: app
          build_system: kmp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.androidBuildSystem == .kmp)
        #expect(config.iosBuildSystem == .native)
    }

    @Test("Shipfile overrides environment variable (iOS)")
    func shipfileOverridesEnvIOS() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        ios:
          build_system: native
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_IOS__BUILD_SYSTEM": "kmp"
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .native)
    }

    @Test("Shipfile overrides environment variable (Android)")
    func shipfileOverridesEnvAndroid() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        android:
          build_system: native
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_ANDROID__BUILD_SYSTEM": "kmp"
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.androidBuildSystem == .native)
    }

    @Test("Environment variable is used when Shipfile does not set build_system (iOS)")
    func envFallbackWhenNoShipfileIOS() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_IOS__BUILD_SYSTEM": "kmp"
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .kmp)
    }

    @Test("Environment variable is used when Shipfile does not set build_system (Android)")
    func envFallbackWhenNoShipfileAndroid() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: MyApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_ANDROID__BUILD_SYSTEM": "flutter"
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.androidBuildSystem == .flutter)
    }

    @Test("Environment variable parsing is case-insensitive and trims whitespace")
    func envCaseAndWhitespaceTolerance() async throws {
        let environment = Environment(env: [
            "SHIPIT_IOS__BUILD_SYSTEM": "  KMP  ",
            "SHIPIT_ANDROID__BUILD_SYSTEM": "Flutter",
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: "/nonexistent")

        #expect(config.iosBuildSystem == .kmp)
        #expect(config.androidBuildSystem == .flutter)
    }

    @Test("Auto-detection inspects the Shipfile's directory, not the cwd")
    func autoDetectsRelativeToShipfileDir() async throws {
        // Place a KMP marker in a temp directory and point --shipfile at a Shipfile
        // *inside* that directory. The Shipfile leaves build_system unset, so the
        // detection step must inspect the Shipfile's directory — not cwd — to find
        // the KMP marker and resolve `.kmp`.
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try """
        plugins {
            kotlin("multiplatform") version "1.9.0"
        }
        """.write(
            to: tempDirectory.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: iosApp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .kmp)
        #expect(config.androidBuildSystem == .kmp)
        #expect(config.platform == .android)
        #expect(config.projectRoot == tempDirectory.path)
    }

    @Test("Flutter auto-detection activates flutter build system")
    func flutterAutoDetectionActivatesFlutterBuildSystem() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try """
        name: demo
        flutter:
          uses-material-design: true
        """.write(
            to: tempDirectory.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try "app:\n  scheme: Runner\n".write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        #expect(config.iosBuildSystem == .flutter)
        #expect(config.androidBuildSystem == .flutter)
    }

    @Test("Reads KMP and Gradle execution settings")
    func readsKMPAndGradleSettings() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        ios:
          build_system: kmp
          kmp_shared_module: coreShared
          kmp_build_target: IosX64
          kmp_archive_target: IosArm64
          kmp_test_task: iosX64Test
        android:
          module: androidApp
          gradle_project_dir: ./android
          gradlew_path: ./android/gradlew
          gradle_flags: ["--configuration-cache", "--stacktrace"]
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let config = try await ConfigResolver(environment: Environment(env: [:]))
            .resolve(shipfilePath: shipfileURL.path)

        #expect(config.kmpSharedModule == "coreShared")
        #expect(config.kmpBuildTarget == "IosX64")
        #expect(config.kmpArchiveTarget == "IosArm64")
        #expect(config.kmpTestTask == "iosX64Test")
        #expect(config.androidModule == "androidApp")
        #expect(config.gradlewPath == "./android/gradlew")
        #expect(config.gradleProjectDir == "./android")
        #expect(config.androidGradleFlags == ["--configuration-cache", "--stacktrace"])
    }

    @Test("Unknown environment value is ignored; Shipfile value wins")
    func unknownEnvFallsThrough() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        ios:
          build_system: kmp
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let environment = Environment(env: [
            "SHIPIT_IOS__BUILD_SYSTEM": "made-up"
        ])
        let resolver = ConfigResolver(environment: environment)
        let config = try await resolver.resolve(shipfilePath: shipfileURL.path)

        // Unknown raw value is ignored — Shipfile value wins.
        #expect(config.iosBuildSystem == .kmp)
    }
}

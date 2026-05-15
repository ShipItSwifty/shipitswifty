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

    @Test("Environment variable overrides Shipfile value (iOS)")
    func envOverridesShipfileIOS() async throws {
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

        #expect(config.iosBuildSystem == .kmp)
    }

    @Test("Environment variable overrides Shipfile value (Android)")
    func envOverridesShipfileAndroid() async throws {
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

        #expect(config.androidBuildSystem == .kmp)
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
    }

    @Test("Unknown environment value falls through to Shipfile or default")
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

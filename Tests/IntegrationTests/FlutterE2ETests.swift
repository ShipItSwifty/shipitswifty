import Foundation
import Testing

/// End-to-end tests against the **real** vendored Flutter app
/// (`Fixtures/flutter-app`) using the real `flutter` toolchain.
///
/// Tiers (see `FixtureBootstrap.swift` tags / `Traits.swift` gates):
/// - **quick** (`test` + `lint`) — runs whenever `flutter` is on PATH.
/// - **build** (`build`) — opt in with `SHIPIT_E2E_BUILD=1`; iOS needs Xcode, Android needs the SDK.
/// - **full** (`archive` + validate) — opt in with `SHIPIT_E2E_FULL=1`.
@Suite("Flutter E2E", .serialized, .requiresFlutterToolchain)
struct FlutterE2ETests {

    private let fixture = FixturePaths.flutterApp

    // MARK: Quick tier

    @Test("flutter test passes", .tags(.e2eQuick))
    func test() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapFlutter(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-e2e",
                directory: tmp,
                contents: shipfileForExternalFlutterProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "test", "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmp,
                timeout: 600
            )
            #expect(result.exitCode == 0, "flutter test failed:\n\(result.output)")
        }
    }

    @Test("flutter analyze is clean", .tags(.e2eQuick))
    func lint() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapFlutter(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-e2e",
                directory: tmp,
                contents: shipfileForExternalFlutterProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "lint", "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmp,
                timeout: 600
            )
            #expect(result.exitCode == 0, "flutter analyze failed:\n\(result.output)")
        }
    }

    // MARK: Build tier (opt-in: SHIPIT_E2E_BUILD=1)

    @Test("flutter builds iOS", .tags(.e2eBuild), .requiresE2EBuild)
    func buildIOS() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapFlutter(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-e2e",
                directory: tmp,
                contents: shipfileForExternalFlutterProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("flutter build ios") {
                try await CLI.run(
                    "build",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "flutter iOS build failed:\n\(result.output)")
        }
    }

    @Test("flutter builds Android APK", .tags(.e2eBuild), .requiresE2EBuild, .requiresAndroid)
    func buildAndroid() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapFlutter(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-e2e",
                directory: tmp,
                contents: shipfileForExternalFlutterProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("flutter build apk") {
                try await CLI.run(
                    "build", "--platform", "android",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "flutter Android build failed:\n\(result.output)")
            let apk = tmp.appendingPathComponent("build/app/outputs/flutter-apk/app-release.apk")
            #expect(FileManager.default.fileExists(atPath: apk.path), "Expected APK at \(apk.path)")
        }
    }

    // MARK: Full tier (opt-in: SHIPIT_E2E_FULL=1)

    @Test("flutter archives Android AAB and validates bundle", .tags(.e2eFull), .requiresE2EFull, .requiresAndroid)
    func archiveAndroid() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapFlutter(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-e2e",
                directory: tmp,
                contents: shipfileForExternalFlutterProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("flutter build appbundle") {
                try await CLI.run(
                    "archive", "--platform", "android",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "flutter Android archive failed:\n\(result.output)")

            let aab = tmp.appendingPathComponent("build/app/outputs/bundle/release/app-release.aab")
            #expect(FileManager.default.fileExists(atPath: aab.path), "Expected AAB at \(aab.path)")

            let validate = try await CLI.run(
                "validate", "bundle", "--platform", "android",
                "--aab", aab.path, "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmp,
                timeout: 600
            )
            #expect(validate.exitCode == 0, "AAB validation failed:\n\(validate.output)")
        }
    }
}

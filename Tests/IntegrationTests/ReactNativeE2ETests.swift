import Foundation
import Testing

/// End-to-end tests against the **real** vendored React Native app
/// (`Fixtures/react-native-app`, pinned to a stable RN release) using real tooling.
///
/// Tiers (see `FixtureBootstrap.swift` tags / `Traits.swift` gates):
/// - **quick** (`test` (Jest) + `lint` (eslint)) — opt in with `SHIPIT_E2E=1`; also needs Node on
///   PATH. `npm install` regenerates `node_modules` into the temp copy, so it is not free.
/// - **build** (`build`) — opt in with `SHIPIT_E2E_BUILD=1`; Android needs the SDK, iOS needs Xcode
///   + CocoaPods (Pods are bootstrapped via `pod install`, not committed).
/// - **full** (`archive` + validate, code signing) — opt in with `SHIPIT_E2E_FULL=1`.
@Suite("React Native E2E", .serialized, .requiresNode)
struct ReactNativeE2ETests {

    private let fixture = FixturePaths.reactNativeApp

    // MARK: Quick tier

    @Test("jest test passes", .tags(.e2eQuick), .requiresE2EQuick)
    func test() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForExternalReactNativeProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "test", "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmp,
                timeout: 900
            )
            #expect(result.exitCode == 0, "RN Jest test failed:\n\(result.output)")
        }
    }

    @Test("eslint is clean", .tags(.e2eQuick), .requiresE2EQuick)
    func lint() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForExternalReactNativeProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "lint", "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmp,
                timeout: 900
            )
            #expect(result.exitCode == 0, "RN eslint failed:\n\(result.output)")
        }
    }

    // MARK: Build tier (opt-in: SHIPIT_E2E_BUILD=1)

    @Test("RN builds Android", .tags(.e2eBuild), .requiresE2EBuild, .requiresAndroid)
    func buildAndroid() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForExternalReactNativeProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("rn build-android") {
                try await CLI.run(
                    "build", "--platform", "android",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "RN Android build failed:\n\(result.output)")
        }
    }

    @Test("RN builds iOS", .tags(.e2eBuild), .requiresE2EBuild, .requiresCocoaPods)
    func buildIOS() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            try await bootstrapReactNativePods(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForExternalReactNativeProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("rn build-ios") {
                try await CLI.run(
                    "build",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "RN iOS build failed:\n\(result.output)")
        }
    }

    // MARK: Full tier (opt-in: SHIPIT_E2E_FULL=1)

    @Test("RN archives Android AAB and validates bundle", .tags(.e2eFull), .requiresE2EFull, .requiresAndroid)
    func archiveAndroid() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForExternalReactNativeProject(at: tmp)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("rn archive android") {
                try await CLI.run(
                    "archive", "--platform", "android",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 1800
                )
            }
            #expect(result.exitCode == 0, "RN Android archive failed:\n\(result.output)")

            let aab = tmp.appendingPathComponent("android/app/build/outputs/bundle/release/app-release.aab")
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

    @Test(
        "RN archives + signs iOS",
        .tags(.e2eFull), .requiresE2EFull, .requiresCocoaPods, .requiresSigningIdentity
    )
    func archiveIOSSigned() async throws {
        try assertReactNativeAppFixtureExists()
        let teamID = try #require(
            ProcessInfo.processInfo.environment["SHIPIT_TEST_TEAM_ID"],
            "Set SHIPIT_TEST_TEAM_ID to a development team for the signed iOS archive tier."
        )
        try await withFixtureCopy(of: fixture) { tmp in
            try await bootstrapReactNativeNode(in: tmp)
            try await bootstrapReactNativePods(in: tmp)
            let shipfile = try makeTempShipfile(
                prefix: "rn-e2e",
                directory: tmp,
                contents: shipfileForReactNativeAppWithSigning(at: tmp, teamID: teamID)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await timed("rn archive ios (signed)") {
                try await CLI.run(
                    "archive",
                    "--shipfile", shipfile.path,
                    workingDirectory: tmp,
                    timeout: 2400
                )
            }
            #expect(result.exitCode == 0, "RN signed iOS archive failed:\n\(result.output)")
        }
    }
}

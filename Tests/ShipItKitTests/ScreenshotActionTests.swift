#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("SnapshotAction")
struct SnapshotActionTests {

    // MARK: - Guards

    @Test("run throws invalidConfiguration when platform is android")
    func runThrowsOnAndroidPlatform() async throws {
        let (executor, _) = makeCaptureExecutor()
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(appScheme: "App", screenshotDevices: ["iPhone 16"]),
            platform: .android
        )

        await #expect(throws: ShipItError.self) {
            _ = try await SnapshotAction().run(
                with: .init(devices: ["iPhone 16"], locales: ["en-US"]),
                context: context
            )
        }
    }

    @Test("run throws when no scheme can be resolved")
    func runThrowsWithoutScheme() async throws {
        let (executor, commands) = makeCaptureExecutor()
        let context = makeTestActionContext(
            executor: executor,
            // No screenshotScheme, no appScheme.
            config: ResolvedConfig(screenshotDevices: ["iPhone 16"]),
            platform: .ios
        )

        await #expect(throws: ShipItError.self) {
            _ = try await SnapshotAction().run(
                with: .init(devices: ["iPhone 16"], locales: ["en-US"]),
                context: context
            )
        }
        #expect(commands().isEmpty, "Should fail before invoking xcodebuild")
    }

    @Test("run throws when no devices are configured")
    func runThrowsWithoutDevices() async throws {
        let (executor, commands) = makeCaptureExecutor()
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(appScheme: "App"),
            platform: .ios
        )

        await #expect(throws: ShipItError.self) {
            _ = try await SnapshotAction().run(
                with: .init(devices: [], locales: ["en-US"]),
                context: context
            )
        }
        #expect(commands().isEmpty, "Should fail before invoking xcodebuild")
    }

    // MARK: - Happy path

    @Test("runs xcodebuild test for each device/locale with destination and locale build setting")
    func capturesAcrossDeviceLocaleMatrix() async throws {
        let outputDir = try makeTempDirectory(prefix: "Snapshots")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let (executor, commands) = makeCaptureExecutor()
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(appProject: "App.xcodeproj"),
            platform: .ios
        )

        let result = try await SnapshotAction().run(
            with: .init(
                devices: ["iPhone 16 Pro", "iPad Pro"],
                locales: ["en-US", "ja"],
                scheme: "AppUITests",
                outputDirectory: outputDir.path
            ),
            context: context
        )

        let invocations = commands().filter { $0.contains("xcodebuild") }
        // 2 devices × 2 locales = 4 test runs.
        #expect(invocations.count == 4)
        #expect(invocations.allSatisfy { $0.contains("-scheme") && $0.contains("AppUITests") })
        #expect(invocations.contains { $0.contains("platform=iOS Simulator,name=iPhone 16 Pro") })
        #expect(invocations.contains { $0.contains("platform=iOS Simulator,name=iPad Pro") })
        #expect(invocations.contains { $0.contains("SNAPSHOT_LOCALE=en-US") })
        #expect(invocations.contains { $0.contains("SNAPSHOT_LOCALE=ja") })

        #expect(result.outputDirectory == outputDir.path)
        #expect(result.failures.isEmpty)
    }

    @Test("falls back to app.scheme when no explicit or screenshot scheme is set")
    func fallsBackToAppScheme() async throws {
        let outputDir = try makeTempDirectory(prefix: "Snapshots")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let (executor, commands) = makeCaptureExecutor()
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(appProject: "App.xcodeproj", appScheme: "FallbackScheme"),
            platform: .ios
        )

        _ = try await SnapshotAction().run(
            with: .init(devices: ["iPhone 16"], locales: ["en-US"], outputDirectory: outputDir.path),
            context: context
        )

        #expect(commands().contains { $0.contains("-scheme") && $0.contains("FallbackScheme") })
    }

    // MARK: - Failure tracking

    @Test("records device/locale in failures when xcodebuild exits non-zero")
    func tracksFailures() async throws {
        let outputDir = try makeTempDirectory(prefix: "Snapshots")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let (executor, _) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "boom", exitCode: 65)
        }
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(appProject: "App.xcodeproj"),
            platform: .ios
        )

        let result = try await SnapshotAction().run(
            with: .init(
                devices: ["iPhone 16"],
                locales: ["en-US"],
                scheme: "AppUITests",
                outputDirectory: outputDir.path
            ),
            context: context
        )

        #expect(result.screenshotCount == 0)
        #expect(result.failures == ["iPhone 16/en-US"])
    }
}
#endif

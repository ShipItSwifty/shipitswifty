#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ValidateBundleAction")
struct ValidateBundleActionTests {
    @Test("auto-discovers native Gradle AAB path when none is provided")
    func autodiscoversNativeAAB() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShipItValidateBundle-\(UUID().uuidString)")
        let bundlePath = tempDirectory
            .appendingPathComponent("app/build/outputs/bundle/release/app-release.aab")
        try FileManager.default.createDirectory(at: bundlePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([UInt8](repeating: 0, count: 2048)).enumerated().map { index, value in
            index < 4 ? [0x50, 0x4B, 0x03, 0x04][index] : value
        }.withUnsafeBufferPointer {
            try Data(buffer: $0).write(to: bundlePath)
        }
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "bundletool ok\n", stderr: "", exitCode: 0)
        }

        let base = ActionContext.mock(executor: executor, platform: .android)
        let shell = ShellContext(
            executor: executor,
            searchPaths: base.shell.searchPaths,
            environment: base.shell.environment,
            workingDirectory: tempDirectory.path,
            defaultTimeout: base.shell.defaultTimeout,
            defaultOutputLimit: base.shell.defaultOutputLimit
        )
        let context = ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                platform: .android,
                androidModule: "app",
                androidBuildVariant: "release"
            ),
            appStoreConnect: base.appStoreConnect,
            googlePlay: base.googlePlay,
            platform: .android
        )

        let result = try await ValidateBundleAction().run(with: .init(), context: context)

        #expect(result.validatedPath == bundlePath.path)
        #expect(result.isAAB == true)
    }
}
#endif

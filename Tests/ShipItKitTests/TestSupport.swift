import AppStoreConnectKit
import Foundation
import GoogleAuthKit
import GooglePlayKit
import SwiftyShell
import TestCommons

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias MockHTTPResponse = StubResponse

extension StubResponse {
    static func json(_ object: [String: Any], statusCode: Int = 200) -> StubResponse {
        StubResponse(
            statusCode: statusCode, headers: ["Content-Type": "application/json"],
            body: try! JSONSerialization.data(withJSONObject: object))
    }

    static func empty(statusCode: Int = 200) -> StubResponse {
        StubResponse(statusCode: statusCode)
    }

    static func error(statusCode: Int, body: String) -> StubResponse {
        .text(body, statusCode: statusCode)
    }
}

final class MockUploadServer: @unchecked Sendable {
    let uploadURL = URL(string: "https://uploads.example.com/upload-part")!
    var receivedBodies: [Data] = []
}

#if os(macOS)
func makeClient(responses: [MockHTTPResponse]) throws -> (client: AppStoreConnectClient, stub: StubbedURLSession) {
    let stub = try StubbedURLSession(
        responses: responses, fallback: .error(statusCode: 500, body: "No queued mock response"))
    let client = AppStoreConnectClient(
        keyID: "KEY",
        issuerID: "ISSUER",
        privateKeyData: Data("placeholder".utf8),
        session: stub.session,
        tokenProvider: { "test-token" }
    )
    return (client, stub)
}
#endif

final class ResponseQueue: Sendable {
    private let storage: TestValueBox<ScriptedValues<StubResponse>>

    init(_ responses: [StubResponse]) {
        storage = TestValueBox(
            ScriptedValues(
                responses, exhaustion: .fallback(.error(statusCode: 500, body: "No queued mock response"))))
    }

    func next() throws -> StubResponse {
        try storage.withValue { try $0.next() }
    }
}

/// Creates a `MockExecutor` that records the `.description` of every command it
/// receives, plus a thread-safe reader closure backed by TestCommons.
///
/// Eliminates the `nonisolated(unsafe) var capturedCommands` boilerplate and
/// replaces it with a TestValueBox capture box that is safe to read after `await`.
///
/// ```swift
/// let (executor, commands) = makeCaptureExecutor { command, _ in
///     ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
/// }
/// let context = ActionContext.mock(executor: executor)
/// _ = try await SomeAction().run(with: options, context: context)
/// #expect(commands().contains { $0.contains("xcodebuild") })
/// ```
///
/// - Parameter handler: Optional custom handler; defaults to returning exit code 0.
/// - Returns: `(executor, commands)` where `commands()` returns the captured list.
func makeCaptureExecutor(
    handler: (@Sendable (Command, ShellContext) async throws -> ShellOutput)? = nil
) -> (executor: MockExecutor, commands: @Sendable () -> [String]) {
    let storage = TestValueBox<[String]>([])
    let executor = MockExecutor { command, context in
        storage.withValue { $0.append(command.description) }
        if let handler {
            return try await handler(command, context)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    return (executor, { storage.get() })
}

func makeTestActionContext(
    executor: MockExecutor,
    config: ResolvedConfig,
    platform: Platform? = nil
) -> ActionContext {
    let shell = ShellContext(executor: executor)
    return makeTestActionContext(shell: shell, executor: executor, config: config, platform: platform)
}

func makeTestActionContext(
    shell: ShellContext,
    config: ResolvedConfig,
    platform: Platform? = nil
) -> ActionContext {
    // Extract executor from shell is not possible, so use a dummy for the mock base
    let dummyExecutor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    return makeTestActionContext(shell: shell, executor: dummyExecutor, config: config, platform: platform)
}

private func makeTestActionContext(
    shell: ShellContext,
    executor: MockExecutor,
    config: ResolvedConfig,
    platform: Platform? = nil
) -> ActionContext {
    let logger = Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self)
    #if os(macOS)
    let base = ActionContext.mock(executor: executor, platform: platform ?? config.platform)
    return ActionContext(
        shell: shell,
        logger: logger,
        config: config,
        appStoreConnect: base.appStoreConnect,
        platform: platform ?? config.platform
    )
    #else
    return ActionContext(
        shell: shell,
        logger: logger,
        config: config,
        platform: platform ?? config.platform
    )
    #endif
}

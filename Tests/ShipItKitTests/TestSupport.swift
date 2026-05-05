import Foundation
import SwiftyShell
import Synchronization

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MockHTTPResponse: Sendable {
    case response(statusCode: Int, headers: [String: String], body: Data)

    static func json(_ object: [String: Any], statusCode: Int = 200) -> MockHTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return .response(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    static func empty(statusCode: Int = 200) -> MockHTTPResponse {
        .response(statusCode: statusCode, headers: [:], body: Data())
    }

    static func error(statusCode: Int, body: String) -> MockHTTPResponse {
        .response(
            statusCode: statusCode,
            headers: ["Content-Type": "text/plain"],
            body: Data(body.utf8)
        )
    }
}

final class MockUploadServer: @unchecked Sendable {
    let uploadURL = URL(string: "https://uploads.example.com/upload-part")!
    var receivedBodies: [Data] = []
}

#if os(macOS)
func makeClient(responses: [MockHTTPResponse]) -> AppStoreConnectClient {
    let queue = ResponseQueue(responses)
    let session = makeMockSession { _ in queue.next() }

    return AppStoreConnectClient(
        keyID: "KEY",
        issuerID: "ISSUER",
        privateKeyData: Data("placeholder".utf8),
        session: session,
        tokenProvider: { "test-token" }
    )
}
#endif

func makeMockSession(handler: @escaping @Sendable (URLRequest) -> MockHTTPResponse) -> URLSession {
    let sessionID = UUID().uuidString
    MockURLProtocol.registerHandler(handler, for: sessionID)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Mock-Session-ID": sessionID]
    return URLSession(configuration: configuration)
}

final class ResponseQueue: @unchecked Sendable {
    private let storage: Mutex<[MockHTTPResponse]>

    init(_ responses: [MockHTTPResponse]) {
        self.storage = .init(responses)
    }

    func next() -> MockHTTPResponse {
        storage.withLock { responses in
            guard !responses.isEmpty else {
                return .error(statusCode: 500, body: "No queued mock response")
            }
            return responses.removeFirst()
        }
    }
}

/// Creates a `MockExecutor` that records the `.description` of every command it
/// receives, plus a thread-safe reader closure.
///
/// Eliminates the `nonisolated(unsafe) var capturedCommands` boilerplate and
/// replaces it with a Mutex-backed capture box that is safe to read after `await`.
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
    let storage = Mutex<[String]>([])
    let executor = MockExecutor { command, context in
        storage.withLock { $0.append(command.description) }
        if let handler {
            return try await handler(command, context)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
    return (executor, { storage.withLock { $0 } })
}

func makeTestActionContext(
    executor: MockExecutor,
    config: ResolvedConfig,
    platform: Platform? = nil
) -> ActionContext {
    let shell = ShellContext(executor: executor)
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

func makeTempDirectory(prefix: String = "ShipItTests") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class MockURLProtocol: URLProtocol {
    private static let handlers: Mutex<[String: @Sendable (URLRequest) -> MockHTTPResponse]> = .init([:])

    static func registerHandler(_ handler: @escaping @Sendable (URLRequest) -> MockHTTPResponse, for sessionID: String) {
        handlers.withLock { $0[sessionID] = handler }
    }

    private static func handler(for sessionID: String) -> (@Sendable (URLRequest) -> MockHTTPResponse)? {
        handlers.withLock { $0[sessionID] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: "X-Mock-Session-ID"),
            let handler = Self.handler(for: sessionID)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = handler(request)
        guard
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension MockHTTPResponse {
    fileprivate var statusCode: Int {
        switch self {
        case .response(let statusCode, _, _):
            statusCode
        }
    }

    fileprivate var headers: [String: String] {
        switch self {
        case .response(_, let headers, _):
            headers
        }
    }

    fileprivate var body: Data {
        switch self {
        case .response(_, _, let body):
            body
        }
    }
}

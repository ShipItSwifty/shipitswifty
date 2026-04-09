import Foundation

@testable import ShipItKit

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

func makeMockSession(handler: @escaping @Sendable (URLRequest) -> MockHTTPResponse) -> URLSession {
    let sessionID = UUID().uuidString
    MockURLProtocol.registerHandler(handler, for: sessionID)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Mock-Session-ID": sessionID]
    return URLSession(configuration: configuration)
}

final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [MockHTTPResponse]

    init(_ responses: [MockHTTPResponse]) {
        self.responses = responses
    }

    func next() -> MockHTTPResponse {
        lock.lock()
        defer { lock.unlock() }

        guard !responses.isEmpty else {
            return .error(statusCode: 500, body: "No queued mock response")
        }
        return responses.removeFirst()
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) -> MockHTTPResponse] = [:]
    private static let lock = NSLock()

    static func registerHandler(_ handler: @escaping @Sendable (URLRequest) -> MockHTTPResponse, for sessionID: String) {
        lock.lock()
        handlers[sessionID] = handler
        lock.unlock()
    }

    private static func handler(for sessionID: String) -> (@Sendable (URLRequest) -> MockHTTPResponse)? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[sessionID]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: "X-Mock-Session-ID"),
              let handler = Self.handler(for: sessionID) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = handler(request)
        guard let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: response.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension MockHTTPResponse {
    var statusCode: Int {
        switch self {
        case .response(let statusCode, _, _):
            statusCode
        }
    }

    var headers: [String: String] {
        switch self {
        case .response(_, let headers, _):
            headers
        }
    }

    var body: Data {
        switch self {
        case .response(_, _, let body):
            body
        }
    }
}

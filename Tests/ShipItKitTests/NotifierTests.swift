import Foundation
import Synchronization
import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injects the transport closure directly rather than going through the shared
/// makeMockSession/MockURLProtocol helper — see WorkloadIdentityFederationClientTests for why
/// (session-ID header routing is unreliable on Linux under concurrent test execution).
@Suite("Notifier")
struct NotifierTests {

    private func response(statusCode: Int) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil,
            headerFields: [:])!
        return (Data(), response)
    }

    @Test("Sends a Slack payload as a JSON POST with the correct content type")
    func sendsSlackPayload() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 200)
        }

        let payload = SlackPayload(text: "Build succeeded!", channel: "#releases", iconEmoji: ":rocket:")
        try await notifier.sendSlack(payload: payload, to: "https://hooks.slack.com/services/T00/B00/XXX")

        let request = try #require(capturedRequest.withLock { $0 })
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString == "https://hooks.slack.com/services/T00/B00/XXX")

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(SlackPayload.self, from: body)
        #expect(decoded.text == "Build succeeded!")
        #expect(decoded.channel == "#releases")
        #expect(decoded.iconEmoji == ":rocket:")
    }

    @Test("Throws an actionable error for an invalid Slack webhook URL")
    func rejectsInvalidSlackURL() async throws {
        let notifier = Notifier { _ in self.response(statusCode: 200) }
        await #expect(throws: ShipItError.self) {
            try await notifier.sendSlack(payload: SlackPayload(text: "hi"), to: "")
        }
    }

    @Test(
        "Throws uploadFailed when Slack returns a non-2xx status",
        arguments: [400, 403, 404, 500])
    func rejectsNon2xxSlackResponse(statusCode: Int) async throws {
        let notifier = Notifier { _ in self.response(statusCode: statusCode) }
        await #expect(throws: ShipItError.self) {
            try await notifier.sendSlack(
                payload: SlackPayload(text: "hi"), to: "https://hooks.slack.com/services/T00/B00/XXX")
        }
    }

    @Test("Sends an arbitrary JSON payload to a custom webhook")
    func sendsCustomWebhookPayload() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 204)
        }

        let payload: JSONValue = .object(["status": .string("green"), "retries": .int(2)])
        try await notifier.sendWebhook(payload: payload, to: "https://example.com/hooks/build")

        let request = try #require(capturedRequest.withLock { $0 })
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(decoded == payload)
    }

    @Test("Throws an actionable error for an invalid webhook URL")
    func rejectsInvalidWebhookURL() async throws {
        let notifier = Notifier { _ in self.response(statusCode: 200) }
        await #expect(throws: ShipItError.self) {
            try await notifier.sendWebhook(payload: .null, to: "")
        }
    }

    @Test("Throws uploadFailed when a custom webhook returns a non-2xx status")
    func rejectsNon2xxWebhookResponse() async throws {
        let notifier = Notifier { _ in self.response(statusCode: 500) }
        await #expect(throws: ShipItError.self) {
            try await notifier.sendWebhook(payload: .null, to: "https://example.com/hooks/build")
        }
    }
}

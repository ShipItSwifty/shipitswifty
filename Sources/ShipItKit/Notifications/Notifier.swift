import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends build notifications to Slack, Teams, Discord, and custom webhooks.
///
/// ## Usage
/// ```swift
/// let notifier = Notifier()
/// let payload = SlackPayload(text: "Build succeeded!", channel: "#releases")
/// try await notifier.sendSlack(payload: payload, to: "https://hooks.slack.com/services/...")
/// ```
public struct Notifier: Sendable {
    /// The raw request/response transport. Matches `URLSession.data(for:)`'s signature exactly,
    /// so production code just wraps a session while tests can inject a closure directly —
    /// deterministic, and independent of any shared URLProtocol-based HTTP mocking (see
    /// `WorkloadIdentityFederationClient` for why: session-ID header routing is unreliable on
    /// Linux under concurrent test execution).
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let logger = Logger.forType(subsystem: "ShipItSwifty", Notifier.self)

    /// Creates a `Notifier`.
    ///
    /// - Parameter session: URL session for HTTP requests. Defaults to `.shared`.
    public init(session: URLSession = .shared) {
        self.transport = { request in try await session.data(for: request) }
    }

    /// Creates a `Notifier` with an injected transport, bypassing `URLSession` entirely.
    ///
    /// Intended for tests: a plain closure is a fully deterministic test double.
    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.transport = transport
    }

    /// Sends a Slack message via an incoming webhook URL.
    ///
    /// - Parameters:
    ///   - payload: The Slack message payload.
    ///   - webhookURL: The Slack incoming webhook URL.
    /// - Throws: `ShipItError.uploadFailed` if the POST fails.
    public func sendSlack(payload: SlackPayload, to webhookURL: String) async throws {
        logger.info("Sending Slack notification")

        guard let url = URL(string: webhookURL) else {
            throw ShipItError.invalidConfiguration(reason: "Invalid Slack webhook URL")
        }

        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ShipItError.uploadFailed(asset: "slack", reason: "Slack webhook returned non-2xx response")
        }

        logger.info("Slack notification sent successfully")
    }

    /// Sends a JSON payload to a custom webhook URL.
    ///
    /// - Parameters:
    ///   - payload: The JSON value to send as the request body.
    ///   - webhookURL: The destination webhook URL.
    /// - Throws: `ShipItError.uploadFailed` if the POST fails.
    public func sendWebhook(payload: JSONValue, to webhookURL: String) async throws {
        logger.info("Sending webhook notification to: \(webhookURL)")

        guard let url = URL(string: webhookURL) else {
            throw ShipItError.invalidConfiguration(reason: "Invalid webhook URL: \(webhookURL)")
        }

        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ShipItError.uploadFailed(asset: webhookURL, reason: "Webhook returned non-2xx response")
        }

        logger.info("Webhook notification sent successfully")
    }
}

/// A Slack incoming webhook message payload.
public struct SlackPayload: Codable, Sendable {
    /// The message text (supports Slack mrkdwn).
    public let text: String

    /// Channel override (e.g. `#releases`). Optional — uses the webhook's default channel if omitted.
    public let channel: String?

    /// Username display name override.
    public let username: String?

    /// Icon emoji override (e.g. `":rocket:"`).
    public let iconEmoji: String?

    /// Rich message attachments.
    public let attachments: [SlackAttachment]?

    /// Creates a `SlackPayload`.
    ///
    /// - Parameters:
    ///   - text: The message text (supports Slack mrkdwn).
    ///   - channel: Optional channel override.
    ///   - username: Display name override. Defaults to `"ShipItSwifty"`.
    ///   - iconEmoji: Icon emoji override (e.g. `":rocket:"`).
    ///   - attachments: Optional rich message attachments.
    public init(
        text: String,
        channel: String? = nil,
        username: String? = "ShipItSwifty",
        iconEmoji: String? = nil,
        attachments: [SlackAttachment]? = nil
    ) {
        self.text = text
        self.channel = channel
        self.username = username
        self.iconEmoji = iconEmoji
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case text, channel, username, attachments
        case iconEmoji = "icon_emoji"
    }
}

/// A Slack message attachment for rich formatting.
public struct SlackAttachment: Codable, Sendable {
    /// Fallback plain-text representation.
    public let fallback: String

    /// Color bar on the left (e.g. `"good"`, `"danger"`, `"#36a64f"`).
    public let color: String?

    /// Short pretext shown above the attachment.
    public let pretext: String?

    /// Main title of the attachment.
    public let title: String?

    /// Body text of the attachment.
    public let text: String?

    /// Creates a `SlackAttachment`.
    ///
    /// - Parameters:
    ///   - fallback: Plain-text fallback description.
    ///   - color: Left-border color (e.g. `"good"`, `"danger"`, `"#36a64f"`).
    ///   - pretext: Short text shown above the attachment.
    ///   - title: Main title of the attachment.
    ///   - text: Body text of the attachment.
    public init(
        fallback: String,
        color: String? = nil,
        pretext: String? = nil,
        title: String? = nil,
        text: String? = nil
    ) {
        self.fallback = fallback
        self.color = color
        self.pretext = pretext
        self.title = title
        self.text = text
    }
}

import Foundation
import OSLog

/// Posts build results to Slack, Teams, Discord, or any custom webhook.
///
/// ## Usage
/// ```swift
/// let result = try await NotifyAction().run(
///     with: .init(slack: .init(message: "Build succeeded!")),
///     context: context
/// )
/// ```
public struct NotifyAction: Action {
    public static let name = "notify"
    public static let description = "Send build notifications to Slack, Teams, Discord, or webhooks"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", NotifyAction.self)

    /// Creates a `NotifyAction`.
    public init() {}

    /// Configuration for the notify action.
    public struct Options: Codable, Sendable {
        /// Slack notification settings.
        public var slack: SlackOptions?

        /// Custom webhook URL to POST to.
        public var webhookUrl: String?

        /// Custom JSON payload for the webhook.
        public var webhookPayload: JSONValue?

        /// Creates `Options` for the notify action.
        ///
        /// At least one of `slack` or `webhookUrl` should be set.
        public init(
            slack: SlackOptions? = nil,
            webhookUrl: String? = nil,
            webhookPayload: JSONValue? = nil
        ) {
            self.slack = slack
            self.webhookUrl = webhookUrl
            self.webhookPayload = webhookPayload
        }
    }

    /// Slack-specific notification options.
    public struct SlackOptions: Codable, Sendable {
        /// The message text to post.
        public var message: String

        /// Channel override (e.g. `#releases`).
        public var channel: String?

        /// Webhook URL override.
        public var webhookUrl: String?

        /// Creates `SlackOptions`.
        public init(message: String, channel: String? = nil, webhookUrl: String? = nil) {
            self.message = message
            self.channel = channel
            self.webhookUrl = webhookUrl
        }
    }

    /// Result of a notify operation.
    public struct Result: Codable, Sendable {
        /// Whether the notification was sent successfully.
        public let sent: Bool

        /// Which channels/webhooks were notified.
        public let destinations: [String]

        /// Creates a `Result`.
        public init(sent: Bool, destinations: [String] = []) {
            self.sent = sent
            self.destinations = destinations
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        logger.info("Sending notifications")
        var destinations: [String] = []
        let notifier = Notifier()

        // Send Slack notification
        if let slack = options.slack {
            let webhookUrl = slack.webhookUrl
                ?? context.config.slackWebhookUrl

            if let webhookUrl {
                logger.info("Sending Slack notification")
                let payload = SlackPayload(
                    text: slack.message,
                    channel: slack.channel ?? context.config.slackChannel
                )
                try await notifier.sendSlack(payload: payload, to: webhookUrl)
                destinations.append("slack")
            } else {
                logger.warning("Slack webhook URL not configured; skipping Slack notification")
            }
        }

        // Send custom webhook
        if let webhookUrl = options.webhookUrl {
            logger.info("Sending webhook to \(webhookUrl)")
            let payload = options.webhookPayload ?? .object(["message": .string("Notification from ShipItSwifty")])
            try await notifier.sendWebhook(payload: payload, to: webhookUrl)
            destinations.append(webhookUrl)
        }

        if destinations.isEmpty {
            logger.warning("No notification destinations configured")
        }

        return Result(sent: !destinations.isEmpty, destinations: destinations)
    }
}

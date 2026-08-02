import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("NotifyAction")
struct NotifyActionTests {

    private func response(statusCode: Int) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil,
            headerFields: [:])!
        return (Data(), response)
    }

    private func makeContext(config: ResolvedConfig) -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor)
        return makeTestActionContext(shell: shell, config: config)
    }

    @Test("Reports no destinations sent when nothing is configured")
    func reportsNoDestinationsByDefault() async throws {
        let action = NotifyAction(notifier: Notifier { _ in self.response(statusCode: 200) })
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        let result = try await action.run(with: .init(), context: makeContext(config: config))

        #expect(result.sent == false)
        #expect(result.destinations.isEmpty)
    }

    @Test("Sends Slack using the option-level webhook URL and reports it as a destination")
    func sendsSlackWithOptionLevelWebhook() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 200)
        }
        let action = NotifyAction(notifier: notifier)
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        let result = try await action.run(
            with: .init(slack: .init(message: "Shipped!", webhookUrl: "https://hooks.slack.com/services/opt")),
            context: makeContext(config: config))

        #expect(result.sent == true)
        #expect(result.destinations == ["slack"])
        #expect(capturedRequest.withLock { $0 }?.url?.absoluteString == "https://hooks.slack.com/services/opt")
    }

    @Test("Falls back to the config-level Slack webhook and channel when options omit them")
    func fallsBackToConfigSlackSettings() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 200)
        }
        let action = NotifyAction(notifier: notifier)
        let config = ResolvedConfig(
            appScheme: "MockApp", bundleID: "com.example.mock",
            slackWebhookUrl: "https://hooks.slack.com/services/config",
            slackChannel: "#builds",
            platform: .ios)

        let result = try await action.run(
            with: .init(slack: .init(message: "Shipped!")), context: makeContext(config: config))

        #expect(result.sent == true)
        #expect(capturedRequest.withLock { $0 }?.url?.absoluteString == "https://hooks.slack.com/services/config")
        let body = try #require(capturedRequest.withLock { $0 }?.httpBody)
        let payload = try JSONDecoder().decode(SlackPayload.self, from: body)
        #expect(payload.channel == "#builds")
    }

    @Test("Option-level Slack channel overrides the config-level default")
    func optionLevelChannelOverridesConfig() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 200)
        }
        let action = NotifyAction(notifier: notifier)
        let config = ResolvedConfig(
            appScheme: "MockApp", bundleID: "com.example.mock",
            slackWebhookUrl: "https://hooks.slack.com/services/config",
            slackChannel: "#builds",
            platform: .ios)

        _ = try await action.run(
            with: .init(slack: .init(message: "Shipped!", channel: "#releases")),
            context: makeContext(config: config))

        let body = try #require(capturedRequest.withLock { $0 }?.httpBody)
        let payload = try JSONDecoder().decode(SlackPayload.self, from: body)
        #expect(payload.channel == "#releases")
    }

    @Test("Skips Slack entirely when no webhook URL is configured anywhere")
    func skipsSlackWithoutWebhookURL() async throws {
        let action = NotifyAction(notifier: Notifier { _ in self.response(statusCode: 200) })
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        let result = try await action.run(with: .init(slack: .init(message: "hi")), context: makeContext(config: config))

        #expect(result.sent == false)
        #expect(result.destinations.isEmpty)
    }

    @Test("Sends a custom webhook and reports the URL as a destination")
    func sendsCustomWebhook() async throws {
        let capturedRequest = Mutex<URLRequest?>(nil)
        let notifier = Notifier { request in
            capturedRequest.withLock { $0 = request }
            return self.response(statusCode: 200)
        }
        let action = NotifyAction(notifier: notifier)
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        let result = try await action.run(
            with: .init(webhookUrl: "https://example.com/hooks/build", webhookPayload: .object(["ok": .bool(true)])),
            context: makeContext(config: config))

        #expect(result.sent == true)
        #expect(result.destinations == ["https://example.com/hooks/build"])
        let body = try #require(capturedRequest.withLock { $0 }?.httpBody)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(decoded == .object(["ok": .bool(true)]))
    }

    @Test("Sends both Slack and a custom webhook, reporting both destinations")
    func sendsBothSlackAndWebhook() async throws {
        let action = NotifyAction(notifier: Notifier { _ in self.response(statusCode: 200) })
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        let result = try await action.run(
            with: .init(
                slack: .init(message: "hi", webhookUrl: "https://hooks.slack.com/services/opt"),
                webhookUrl: "https://example.com/hooks/build"),
            context: makeContext(config: config))

        #expect(result.sent == true)
        #expect(result.destinations == ["slack", "https://example.com/hooks/build"])
    }

    @Test("Propagates a Slack delivery failure instead of silently continuing")
    func propagatesSlackFailure() async throws {
        let action = NotifyAction(notifier: Notifier { _ in self.response(statusCode: 500) })
        let config = ResolvedConfig(appScheme: "MockApp", bundleID: "com.example.mock", platform: .ios)

        await #expect(throws: ShipItError.self) {
            try await action.run(
                with: .init(slack: .init(message: "hi", webhookUrl: "https://hooks.slack.com/services/opt")),
                context: makeContext(config: config))
        }
    }
}

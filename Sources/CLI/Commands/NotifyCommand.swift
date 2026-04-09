import ArgumentParser
import ShipItKit

/// Send build notifications to Slack, Teams, Discord, or webhooks.
struct NotifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send build notifications to Slack, Teams, or webhooks"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Slack message text")
    var message: String?

    @Option(name: .long, help: "Slack channel override (e.g. #releases)")
    var channel: String?

    @Option(name: .long, help: "Webhook URL to POST to")
    var webhookUrl: String?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            var options = NotifyAction.Options()

            if let message {
                options = NotifyAction.Options(
                    slack: NotifyAction.SlackOptions(message: message, channel: channel)
                )
            } else if let webhookUrl {
                options = NotifyAction.Options(webhookUrl: webhookUrl)
            }

            if global.dryRun {
                formatter.print("DRY RUN: Would send notification")
                return
            }

            let result = try await NotifyAction().run(with: options, context: context)
            outputResult(action: "notify", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

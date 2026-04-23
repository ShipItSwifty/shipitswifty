extension BuildTimingAction {
    private static let logger = Logger.forType(
        subsystem: "BuildTimingPlugin",
        BuildTimingAction.self
    )

    public init() {}

    public func run(
        with options: Options,
        context: ActionContext
    ) async throws -> Result {
        let parts = options.command.split(separator: " ").map(String.init)
        guard let executable = parts.first else {
            throw ShipItError.invalidConfiguration(
                reason: "build-timing: 'command' must not be empty."
            )
        }
        let arguments = Array(parts.dropFirst())

        var command = Command(executable, arguments: arguments)
        if let cwd = options.workingDirectory {
            command = command.workingDirectory(cwd)
        }

        let start = ContinuousClock.now
        let outcome = try await command.run(in: context.shell)
        let elapsed = ContinuousClock.now - start

        let seconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1e18
        Self.logger.info("\(options.command) took \(seconds, format: .fixed(precision: 2))s")

        return Result(
            command: options.command,
            durationSeconds: seconds,
            exitCode: outcome.exitCode
        )
    }
}

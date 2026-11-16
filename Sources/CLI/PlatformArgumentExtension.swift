import ArgumentParser
import ShipItKit

// MARK: - ExpressibleByArgument conformance for Platform

/// Makes `Platform` usable as an `@Option` value in ArgumentParser commands.
///
/// Enables `--platform ios` and `--platform android` on all CLI commands.
extension Platform: ExpressibleByArgument {}

/// Makes `SuggestionGoal` usable as `--goal` and `--workflow` values.
extension SuggestionGoal: ExpressibleByArgument {}

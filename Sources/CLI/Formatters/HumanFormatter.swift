import ArgumentParser
import Foundation
import SwiftyTerminal

extension ColorMode: @retroactive ExpressibleByArgument {}

/// Formats output for human-readable console display.
///
/// Used by CLI commands when `--output human` (the default) is selected.
/// Produces colored, structured output with headers, key-value pairs,
/// checkmarks, and progress indicators.
public struct HumanFormatter: Sendable {
    private let console: Console

    public init(useColors: Bool = true) {
        self.console = Console(colorMode: useColors ? .auto : .never)
    }

    init(colorMode: ColorMode) {
        self.console = Console(colorMode: colorMode)
    }

    private var styler: Styler { console.styler }

    // MARK: - Output Methods

    /// Print a plain message.
    public func print(_ message: String) {
        console.print(styledMessage(message))
    }

    /// Print a section header.
    public func printHeader(_ title: String) {
        console.header(title)
    }

    /// Print a divider line.
    public func printDivider() {
        console.divider()
    }

    /// Print a key-value pair.
    public func printKV(_ key: String, _ value: String) {
        console.keyValue(key, styledValue(value))
    }

    /// Print a success message with a checkmark.
    public func printSuccess(_ message: String) {
        console.success(message)
    }

    /// Print an error message.
    public func printError(_ message: String) {
        console.error(message)
    }

    /// Print a warning message.
    public func printWarning(_ message: String) {
        console.warning(message)
    }

    /// Print a pass/fail checkmark for doctor checks.
    public func printCheckmark(_ name: String, passed: Bool) {
        console.check(name, passed: passed)
    }

    /// Print an action result in human-readable form.
    public func printResult<T: Codable & Sendable>(action: String, result: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result),
            let json = String(data: data, encoding: .utf8)
        {
            console.print("\n\(completed(action))\n\(json)")
        } else {
            console.print("\n\(completed(action))")
        }
    }

    private func styledMessage(_ message: String) -> String {
        guard !message.isEmpty else { return message }

        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)
        if trimmedMessage.hasPrefix("DRY RUN:") {
            return yellow(message)
        }

        if trimmedMessage == "Next steps:" {
            return bold(cyan(message))
        }

        if isCommandExample(trimmedMessage) {
            return magenta(message)
        }

        if isNumberedStep(trimmedMessage) {
            return cyan(message)
        }

        return cyan(message)
    }

    private func styledValue(_ value: String) -> String {
        if value == "(not set)" {
            return dim(value)
        }

        if value.hasPrefix("[REDACTED]") {
            return yellow(value)
        }

        if value.contains("[loaded]") || value.contains("[from ") {
            return green(value)
        }

        return value
    }

    private func isCommandExample(_ message: String) -> Bool {
        message.hasPrefix("shipit ") || message.hasPrefix("export ")
    }

    private func isNumberedStep(_ message: String) -> Bool {
        guard let first = message.first, first.isNumber else { return false }
        return message.contains(". ")
    }

    private func completed(_ action: String) -> String {
        "\(styler.green(console.symbols.success)) \(styler.apply(action, .green, .bold)) completed"
    }

    private func dim(_ text: String) -> String { styler.dim(text) }
    private func bold(_ text: String) -> String { styler.bold(text) }
    private func cyan(_ text: String) -> String { styler.cyan(text) }
    private func green(_ text: String) -> String { styler.green(text) }
    private func magenta(_ text: String) -> String { styler.magenta(text) }
    private func yellow(_ text: String) -> String { styler.yellow(text) }
}

import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ConsoleColorMode: String, ExpressibleByArgument, Sendable {
    case auto
    case always
    case never
}

/// Formats output for human-readable console display.
///
/// Used by CLI commands when `--output human` (the default) is selected.
/// Produces colored, structured output with headers, key-value pairs,
/// checkmarks, and progress indicators.
public struct HumanFormatter: Sendable {
    private let useColors: Bool

    public init(useColors: Bool = true) {
        self.useColors = useColors && Self.environmentSupportsColor()
    }

    init(colorMode: ConsoleColorMode) {
        self.useColors = Self.shouldUseColors(for: colorMode)
    }

    // MARK: - Output Methods

    /// Print a plain message.
    public func print(_ message: String) {
        Swift.print(styledMessage(message))
    }

    /// Print a section header.
    public func printHeader(_ title: String) {
        Swift.print("\n\(cyan(bold("=== \(title) ===")))")
    }

    /// Print a divider line.
    public func printDivider() {
        Swift.print(dim(String(repeating: "-", count: 60)))
    }

    /// Print a key-value pair.
    public func printKV(_ key: String, _ value: String) {
        let paddedKey = key.padding(toLength: max(key.count, 30), withPad: " ", startingAt: 0)
        Swift.print("  \(cyan(paddedKey)) \(styledValue(value))")
    }

    /// Print a success message with a checkmark.
    public func printSuccess(_ message: String) {
        Swift.print("\(green("✓")) \(green(message))")
    }

    /// Print an error message.
    public func printError(_ message: String) {
        Swift.print("\(red("✗")) \(red(message))")
    }

    /// Print a warning message.
    public func printWarning(_ message: String) {
        Swift.print("\(yellow("⚠")) \(yellow(message))")
    }

    /// Print a pass/fail checkmark for doctor checks.
    public func printCheckmark(_ name: String, passed: Bool) {
        let symbol = passed ? green("✓") : red("✗")
        let formattedName = passed ? green(name) : red(name)
        Swift.print("  \(symbol) \(formattedName)")
    }

    /// Print an action result in human-readable form.
    public func printResult<T: Codable & Sendable>(action: String, result: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result),
            let json = String(data: data, encoding: .utf8)
        {
            Swift.print("\n\(green("✓")) \(green(bold(action))) completed\n\(json)")
        } else {
            Swift.print("\n\(green("✓")) \(green(bold(action))) completed")
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

    private static func shouldUseColors(for colorMode: ConsoleColorMode) -> Bool {
        switch colorMode {
        case .auto:
            environmentSupportsColor()
        case .always:
            true
        case .never:
            false
        }
    }

    private static func environmentSupportsColor() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let isInteractiveTerminal = isatty(STDOUT_FILENO) != 0
        let term = environment["TERM"]?.lowercased()

        return environment["NO_COLOR"] == nil
            && term != "dumb"
            && isInteractiveTerminal
    }

    // MARK: - ANSI Color Helpers

    private func dim(_ text: String) -> String {
        useColors ? "\u{001B}[2m\(text)\u{001B}[0m" : text
    }

    private func bold(_ text: String) -> String {
        useColors ? "\u{001B}[1m\(text)\u{001B}[0m" : text
    }

    private func cyan(_ text: String) -> String {
        useColors ? "\u{001B}[36m\(text)\u{001B}[0m" : text
    }

    private func green(_ text: String) -> String {
        useColors ? "\u{001B}[32m\(text)\u{001B}[0m" : text
    }

    private func magenta(_ text: String) -> String {
        useColors ? "\u{001B}[35m\(text)\u{001B}[0m" : text
    }

    private func red(_ text: String) -> String {
        useColors ? "\u{001B}[31m\(text)\u{001B}[0m" : text
    }

    private func yellow(_ text: String) -> String {
        useColors ? "\u{001B}[33m\(text)\u{001B}[0m" : text
    }
}

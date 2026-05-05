#if os(macOS)
import Foundation

/// A typed option for the `xcodegen` command.
public struct XcodeGenOption: Sendable, Equatable, Hashable {

    /// The raw arguments emitted for this option.
    public let arguments: [String]

    /// Creates an `XcodeGenOption` from raw arguments.
    public init(_ arguments: String...) {
        precondition(!arguments.isEmpty, "An xcodegen option must include at least one argument.")
        self.arguments = arguments
    }

    private init(arguments: [String]) {
        precondition(!arguments.isEmpty, "An xcodegen option must include at least one argument.")
        self.arguments = arguments
    }

    /// Creates a custom xcodegen option.
    public static func custom(_ flag: String, values: String...) -> Self {
        Self(arguments: [flag] + values)
    }

    // MARK: - Common Options

    /// `--spec <path>` — Path to the project spec file (default: `project.yml`).
    public static func spec(_ path: String) -> Self {
        Self("--spec", path)
    }

    /// `--project <path>` — The path to the directory where the project will be generated.
    public static func project(_ path: String) -> Self {
        Self("--project", path)
    }

    /// `--no-cache` — Disable the spec caching.
    public static let noCache = Self("--no-cache")

    /// `--quiet` — Suppress non-error output.
    public static let quiet = Self("--quiet")

    /// `--no-env` — Disable environment variable expansion in the spec.
    public static let noEnv = Self("--no-env")

    /// `--use-cache` — Use the cache (opposite of `--no-cache`).
    public static let useCache = Self("--use-cache")

    /// `--cache-path <path>` — Path to the cache file.
    public static func cachePath(_ path: String) -> Self {
        Self("--cache-path", path)
    }

    /// `--type <value>` — Dump type: `parsed`, `resolved`, or `plists`.
    public static func type(_ value: String) -> Self {
        Self("--type", value)
    }

    /// `--file <path>` — Write output to a file instead of stdout (for `dump`).
    public static func file(_ path: String) -> Self {
        Self("--file", path)
    }
}
#endif

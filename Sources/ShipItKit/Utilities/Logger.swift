@_exported import Logging

extension Logger {
    /// Creates a `Logger` scoped to a specific type within a subsystem.
    ///
    /// Provides consistent logger naming across ShipItSwifty by using the type name
    /// as the category. Built on `swift-log` so it works on macOS and Linux alike.
    ///
    /// ## Usage
    /// ```swift
    /// private let logger = Logger.forType(subsystem: "ShipItSwifty", BuildAction.self)
    /// logger.info("Starting build for scheme: \(scheme)")
    /// ```
    ///
    /// - Parameters:
    ///   - subsystem: The subsystem identifier, e.g. `"ShipItSwifty"`.
    ///   - type: The type to use as the log category.
    /// - Returns: A `Logger` whose label is `"<subsystem>.<TypeName>"`.
    public static func forType<T>(subsystem: String, _ type: T.Type) -> Logger {
        Logger(label: "\(subsystem).\(String(describing: T.self))")
    }
}

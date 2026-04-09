import OSLog

extension Logger {
    /// Creates a `Logger` scoped to a specific type within a subsystem.
    ///
    /// Provides consistent logger naming across ShipItSwifty by using the type name
    /// as the category. This makes it easy to filter logs by component in Console.app.
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
    /// - Returns: A `Logger` with category set to the type's name.
    public static func forType<T>(subsystem: String, _ type: T.Type) -> Logger {
        Logger(subsystem: subsystem, category: String(describing: T.self))
    }
}

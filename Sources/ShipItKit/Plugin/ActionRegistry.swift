import OSLog

/// Central registry for built-in and plugin-provided actions.
///
/// All methods are `async` because `ActionRegistry` is an `actor` — callers
/// must `await` access to serialize concurrent registration and lookup.
///
/// ## Usage
/// ```swift
/// let registry = ActionRegistry()
/// try await registry.register(BuildAction.descriptor(for: BuildAction()))
/// let descriptor = await registry.descriptor(named: "build")
/// ```
public actor ActionRegistry {
    private var descriptors: [String: ActionDescriptor] = [:]
    private let logger = Logger.forType(subsystem: "ShipItSwifty", ActionRegistry.self)

    /// Creates an empty `ActionRegistry`.
    public init() {}

    /// Register a new action descriptor.
    ///
    /// - Parameter descriptor: The descriptor to register.
    /// - Throws: ``ShipItError/duplicateAction`` if an action with the same name is already registered.
    public func register(_ descriptor: ActionDescriptor) throws {
        guard descriptors[descriptor.name] == nil else {
            throw ShipItError.duplicateAction(name: descriptor.name)
        }
        descriptors[descriptor.name] = descriptor
        logger.debug("Registered action: \(descriptor.name)")
    }

    /// Look up a registered action descriptor by name.
    ///
    /// - Parameter name: The action's registered name.
    /// - Returns: The descriptor if found, otherwise `nil`.
    public func descriptor(named name: String) -> ActionDescriptor? {
        descriptors[name]
    }

    /// Returns all registered action descriptors.
    ///
    /// - Returns: An array of all registered descriptors.
    public func allDescriptors() -> [ActionDescriptor] {
        Array(descriptors.values)
    }
}

import OSLog

/// Manages a collection of statically linked `ShipItPlugin` types and
/// registers their action descriptors into an `ActionRegistry`.
///
/// `PluginRegistry` is the bootstrap point for extending ShipItSwifty with
/// custom actions. Built-in actions are registered first, followed by plugins
/// in registration order.
///
/// ## Usage
/// ```swift
/// let registry = ActionRegistry()
/// let plugins = PluginRegistry()
/// plugins.register(MyCustomPlugin.self)
/// try await plugins.registerAll(into: registry)
/// ```
public actor PluginRegistry {
    private var pluginTypes: [any ShipItPlugin.Type] = []
    private let logger = Logger.forType(subsystem: "ShipItSwifty", PluginRegistry.self)

    /// Creates an empty `PluginRegistry`.
    public init() {}

    /// Register a plugin type for later descriptor registration.
    ///
    /// - Parameter pluginType: The plugin's metatype (e.g. `MyPlugin.self`).
    public func register(_ pluginType: any ShipItPlugin.Type) {
        pluginTypes.append(pluginType)
        logger.debug("Registered plugin: \(pluginType.name)")
    }

    /// Register all plugin-provided action descriptors into the given `ActionRegistry`.
    ///
    /// Iterates over all registered plugin types and calls `registry.register(_:)`
    /// for each action descriptor they provide.
    ///
    /// - Parameter registry: The `ActionRegistry` to populate.
    /// - Throws: ``ShipItError/duplicateAction(name:)`` if a plugin registers a name collision.
    public func registerAll(into registry: ActionRegistry) async throws {
        for pluginType in pluginTypes {
            logger.info("Loading plugin: \(pluginType.name) — \(pluginType.description)")
            for descriptor in pluginType.actions {
                try await registry.register(descriptor)
            }
        }
    }

    /// The names of all registered plugins, in registration order.
    public var registeredPluginNames: [String] {
        pluginTypes.map { $0.name }
    }
}

import Foundation
import Logging

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
    /// - Throws: ``ShipItError/duplicateAction(name:)`` if an action with the same name is already registered.
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

    /// Register all user-defined composite actions from a Shipfile.
    ///
    /// Built-in actions MUST already be registered before calling this so
    /// collision detection can distinguish user composites from built-ins.
    ///
    /// Performs three static checks before registering anything:
    /// 1. No composite may reuse a built-in (already-registered) action name.
    /// 2. No two composites may share a name (guaranteed by the dictionary).
    /// 3. The graph of composite → composite references must be acyclic.
    ///
    /// - Parameter customActions: The `custom_actions` map from the resolved Shipfile.
    /// - Throws: ``ShipItError/duplicateAction(name:)`` for name collisions,
    ///   ``ShipItError/invalidConfiguration(reason:)`` for cycles.
    public func registerCustomActions(_ customActions: [String: CustomActionConfig]) throws {
        guard !customActions.isEmpty else { return }

        for name in customActions.keys where descriptors[name] != nil {
            throw ShipItError.invalidConfiguration(
                reason: "Custom action '\(name)' collides with a built-in action. Rename the custom action."
            )
        }

        if let cycle = Self.detectCycle(in: customActions) {
            throw ShipItError.invalidConfiguration(
                reason: "Custom action cycle detected: \(cycle.joined(separator: " -> "))."
            )
        }

        for (name, config) in customActions.sorted(by: { $0.key < $1.key }) {
            let descriptor = CompositeAction.descriptor(name: name, config: config, registry: self)
            descriptors[name] = descriptor
            logger.debug("Registered custom action: \(name)")
        }
    }

    /// Returns the first detected cycle across composite-to-composite step
    /// references, or `nil` when the graph is acyclic.
    static func detectCycle(in customActions: [String: CustomActionConfig]) -> [String]? {
        let names = Set(customActions.keys)
        var visited: Set<String> = []
        var stack: [String] = []
        var onStack: Set<String> = []

        func dfs(_ node: String) -> [String]? {
            if onStack.contains(node) {
                // Extract the cycle from the stack.
                if let idx = stack.firstIndex(of: node) {
                    return Array(stack[idx...]) + [node]
                }
                return [node, node]
            }
            if visited.contains(node) { return nil }
            visited.insert(node)
            stack.append(node)
            onStack.insert(node)

            if let config = customActions[node] {
                for step in config.steps where names.contains(step.action) {
                    if let cycle = dfs(step.action) { return cycle }
                }
            }

            stack.removeLast()
            onStack.remove(node)
            return nil
        }

        for name in customActions.keys.sorted() {
            if let cycle = dfs(name) { return cycle }
        }
        return nil
    }
}

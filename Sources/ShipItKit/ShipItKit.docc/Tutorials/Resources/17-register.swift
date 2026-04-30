import BuildTimingPlugin
import ShipItKit

let registry = ActionRegistry()
try await registerBuiltInActions(into: registry)

let plugins = PluginRegistry()
await plugins.register(BuildTimingPlugin.self)
try await plugins.registerAll(into: registry)

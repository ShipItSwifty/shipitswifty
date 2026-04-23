import ShipItKit

public struct BuildTimingPlugin: ShipItPlugin {
    public static let name = "build-timing"
    public static let description = "Adds a build-timing action that wraps any other action."
    public static let actions: [ActionDescriptor] = [
        BuildTimingAction.descriptor(for: BuildTimingAction()),
    ]
}

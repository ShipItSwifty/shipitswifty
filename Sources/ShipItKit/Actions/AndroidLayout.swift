public struct AndroidLayoutAction: AndroidCLIFamilyAction {
    public static let name = "android-layout"
    public static let description = "Inspect the active Android UI layout as JSON"
    static let family: [String] = []
    static let operations: Set<String> = ["layout"]
    public init() {}
}

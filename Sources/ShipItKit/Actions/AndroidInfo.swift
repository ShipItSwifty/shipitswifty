public struct AndroidInfoAction: AndroidCLIFamilyAction {
    public static let name = "android-info"
    public static let description = "Print AndroidCLI environment information"
    static let family: [String] = []
    static let operations: Set<String> = ["info"]
    public init() {}
}

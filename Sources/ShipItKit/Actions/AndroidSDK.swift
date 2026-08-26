public struct AndroidSDKAction: AndroidCLIFamilyAction {
    public static let name = "android-sdk"
    public static let description = "Install, update, remove, or list Android SDK packages"
    static let family = ["sdk"]
    static let operations: Set<String> = ["install", "update", "remove", "list"]
    static let mutationOperations: Set<String> = ["install", "update", "remove"]
    public init() {}
}

public struct AndroidInitAction: AndroidCLIFamilyAction {
    public static let name = "android-init"
    public static let description = "Initialize AndroidCLI agent configuration"
    static let family: [String] = []
    static let operations: Set<String> = ["init"]
    static let mutationOperations: Set<String> = ["init"]
    public init() {}
}

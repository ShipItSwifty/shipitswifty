public struct AndroidRunAction: AndroidCLIFamilyAction {
    public static let name = "android-run"
    public static let description = "Install and launch prebuilt APKs with AndroidCLI"
    static let family: [String] = []
    static let operations: Set<String> = ["run"]
    static let mutationOperations: Set<String> = ["run"]
    public init() {}
}

public struct AndroidCLIVersionAction: AndroidCLIFamilyAction {
    public static let name = "android-version"
    public static let description = "Print the installed AndroidCLI version"
    static let family: [String] = []
    static let operations: Set<String> = ["--version"]
    public init() {}
}

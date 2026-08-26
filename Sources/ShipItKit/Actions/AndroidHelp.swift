public struct AndroidHelpAction: AndroidCLIFamilyAction {
    public static let name = "android-help"
    public static let description = "Show AndroidCLI help"
    static let family: [String] = []
    static let operations: Set<String> = ["help"]
    public init() {}
}

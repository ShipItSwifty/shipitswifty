public struct AndroidDescribeAction: AndroidCLIFamilyAction {
    public static let name = "android-describe"
    public static let description = "Describe Android project targets and artifacts with AndroidCLI"
    static let family: [String] = []
    static let operations: Set<String> = ["describe"]
    public init() {}
}

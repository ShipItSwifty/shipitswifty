public struct AndroidDocsAction: AndroidCLIFamilyAction {
    public static let name = "android-docs"
    public static let description = "Search or fetch the official Android Knowledge Base"
    static let family = ["docs"]
    static let operations: Set<String> = ["search", "fetch"]
    public init() {}
}

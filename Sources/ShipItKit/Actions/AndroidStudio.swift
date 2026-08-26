public struct AndroidStudioAction: AndroidCLIFamilyAction {
    public static let name = "android-studio"
    public static let description = "Use Android Studio analysis and navigation through AndroidCLI"
    static let family = ["studio"]
    static let operations: Set<String> = ["check", "analyze-file", "find-declaration", "find-usages", "open-file", "render-compose-preview", "version-lookup"]
    public init() {}
}

public struct AndroidInstallAction: AndroidCLIFamilyAction {
    public static let name = "android-install"
    public static let description = "Install prebuilt APKs with AndroidCLI"
    static let family: [String] = []
    static let operations: Set<String> = ["install"]
    static let mutationOperations: Set<String> = ["install"]
    public init() {}
}

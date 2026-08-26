public struct AndroidScreenAction: AndroidCLIFamilyAction {
    public static let name = "android-screen"
    public static let description = "Capture or resolve annotated Android device screens"
    static let family = ["screen"]
    static let operations: Set<String> = ["capture", "resolve"]
    public init() {}
}

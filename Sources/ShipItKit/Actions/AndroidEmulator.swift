public struct AndroidEmulatorAction: AndroidCLIFamilyAction {
    public static let name = "android-emulator"
    public static let description = "Create, start, stop, list, or remove Android emulators with AndroidCLI"
    static let family = ["emulator"]
    static let operations: Set<String> = ["create", "start", "stop", "list", "remove"]
    static let mutationOperations: Set<String> = ["create", "start", "stop", "remove"]
    public init() {}
}

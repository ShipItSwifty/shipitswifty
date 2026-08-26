public struct AndroidUpdateAction: AndroidCLIFamilyAction {
    public static let name = "android-update"
    public static let description = "Update AndroidCLI"
    static let family: [String] = []
    static let operations: Set<String> = ["update"]
    static let mutationOperations: Set<String> = ["update"]
    public init() {}
}

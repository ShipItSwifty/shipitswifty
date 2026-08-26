public struct AndroidCreateAction: AndroidCLIFamilyAction {
    public static let name = "android-create"
    public static let description = "Create Android projects or list templates with AndroidCLI"
    static let family = ["create"]
    static let operations: Set<String> = ["create", "list"]
    static let mutationOperations: Set<String> = ["create"]

    static func commandArguments(operation: String?, arguments: [String]) -> [String] {
        switch operation {
        case "create": ["create"] + arguments
        case "list": ["create", "--list"] + arguments
        default: arguments
        }
    }

    public init() {}
}

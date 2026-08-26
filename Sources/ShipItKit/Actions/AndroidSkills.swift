public struct AndroidSkillsAction: AndroidCLIFamilyAction {
    public static let name = "android-skills"
    public static let description = "Add, remove, list, or find official Android agent skills"
    static let family = ["skills"]
    static let operations: Set<String> = ["add", "remove", "list", "find"]
    static let mutationOperations: Set<String> = ["add", "remove"]
    public init() {}
}

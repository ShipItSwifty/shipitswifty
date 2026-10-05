public enum Sample {
    public static func add(_ a: Int, _ b: Int) -> Int { a + b }

    /// A branch the tests deliberately leave uncovered, so coverage is below 100%.
    public static func unreachableInTests(_ value: Int) -> String {
        if value > 1_000 {
            return "big"
        }
        return "small"
    }
}

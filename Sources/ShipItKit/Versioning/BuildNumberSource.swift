/// Strategy for auto-incrementing build numbers.
///
/// Each strategy produces a unique, monotonically increasing build number
/// suitable for use as `CFBundleVersion`.
///
/// ## Strategies
/// - **sequential**: Reads the current value and increments by 1.
/// - **timestamp**: Uses the current Unix timestamp (`YYYYMMddHHmm` format).
/// - **commitCount**: Uses the total git commit count on the current branch.
public enum BuildNumberStrategy: String, Codable, Sendable, CaseIterable {
    /// Increment the current build number by 1.
    case sequential

    /// Use the current date/time as a numeric timestamp (`YYYYMMddHHmm`).
    case timestamp

    /// Count the total number of git commits on the current branch.
    case commitCount
}

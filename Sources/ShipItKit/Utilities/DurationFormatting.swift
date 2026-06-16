import Foundation

extension Duration {
    /// The duration as a floating-point number of seconds.
    ///
    /// `Duration` only exposes integer `components` (whole seconds + attoseconds); this combines
    /// them into a single `Double` suitable for JSON output and logging.
    public var totalSeconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}

/// Formats an elapsed time (in seconds) for human-readable logs.
///
/// - `< 60s` → `"42.3s"`
/// - `>= 60s` → `"15m 1s"` (whole seconds once minutes are involved)
///
/// Used for per-step and per-action duration log lines so a 15-minute build reads as `15m 1s`
/// rather than `901.3s`. Machine-readable output (`--output json`) keeps raw seconds.
public func formatDurationSeconds(_ seconds: Double) -> String {
    guard seconds >= 60 else {
        return String(format: "%.1fs", seconds)
    }
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let remainder = total % 60
    return "\(minutes)m \(remainder)s"
}

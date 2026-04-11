import Foundation
import OSLog

/// Tracks App Store Connect API rate limits and enforces backoff.
///
/// Reads `X-Rate-Limit` headers from responses and delays requests
/// when approaching the hourly threshold (default: pause at 90% usage).
///
/// Apple's rate limit header format:
/// ```
/// X-Rate-Limit: user-hour-lim:3500;user-hour-rem:2998
/// ```
///
/// ## Usage
/// ```swift
/// let limiter = RateLimiter()
/// // Before each API request:
/// await limiter.throttleIfNeeded()
/// // After each response:
/// await limiter.update(from: responseHeaders)
/// ```
public actor RateLimiter {
    /// The fraction of the limit at which throttling begins (0.9 = 90% used).
    public let throttleThreshold: Double

    private var hourlyLimit: Int?
    private var hourlyRemaining: Int?
    private let logger = Logger.forType(subsystem: "ShipItSwifty", RateLimiter.self)

    /// Creates a `RateLimiter`.
    ///
    /// - Parameter throttleThreshold: Fraction (0–1) of hourly limit at which to pause.
    ///   Defaults to `0.9` (pause when 90% of the limit is consumed).
    public init(throttleThreshold: Double = 0.9) {
        self.throttleThreshold = throttleThreshold
    }

    /// Delay execution if the rate limit is approaching the throttle threshold.
    ///
    /// Sleeps for a backoff period if fewer than `(1 - throttleThreshold) * limit` requests remain.
    public func throttleIfNeeded() async {
        guard let limit = hourlyLimit, let remaining = hourlyRemaining else {
            // No rate limit data yet; proceed
            return
        }

        let usageFraction = Double(limit - remaining) / Double(limit)
        if usageFraction >= throttleThreshold {
            let backoffSeconds: Double = 5.0
            logger.warning("Rate limit at \(Int(usageFraction * 100))% (\(remaining)/\(limit) remaining). Throttling for \(backoffSeconds)s.")
            try? await Task.sleep(for: .seconds(backoffSeconds))
        } else {
            logger.debug("Rate limit OK: \(remaining)/\(limit) remaining (\(Int(usageFraction * 100))% used)")
        }
    }

    /// Update rate limit state from an HTTP response's headers.
    ///
    /// Parses `X-Rate-Limit: user-hour-lim:3500;user-hour-rem:2998`.
    ///
    /// - Parameter headers: Dictionary of HTTP response header fields.
    public func update(from headers: [String: String]) {
        guard let header = headers["X-Rate-Limit"] ?? headers["x-rate-limit"] else {
            return
        }
        parse(header: header)
    }

    // MARK: - Private

    private func parse(header: String) {
        // Format: "user-hour-lim:3500;user-hour-rem:2998"
        let parts = header.components(separatedBy: ";")
        for part in parts {
            let kv = part.components(separatedBy: ":")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            if key == "user-hour-lim", let intValue = Int(value) {
                hourlyLimit = intValue
            } else if key == "user-hour-rem", let intValue = Int(value) {
                hourlyRemaining = intValue
            }
        }
        if let limit = hourlyLimit, let remaining = hourlyRemaining {
            logger.debug("Rate limit updated: \(remaining)/\(limit) remaining this hour")
        }
    }
}

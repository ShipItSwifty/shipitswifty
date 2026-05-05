import Foundation
import Logging

/// Defines retry behavior with exponential backoff for transient failures.
///
/// Use `RetryPolicy` to wrap any throwing async operation with automatic retry logic.
/// Each successive attempt waits longer before retrying (exponential backoff).
///
/// ## Usage
/// ```swift
/// let policy = RetryPolicy(maxAttempts: 3, initialDelay: .seconds(1), multiplier: 2.0)
/// let result = try await policy.execute {
///     try await uploadChunk(data: data)
/// }
/// ```
public struct RetryPolicy: Sendable {
    /// Maximum number of attempts (including the first try).
    public let maxAttempts: Int

    /// Delay before the second attempt. Subsequent delays are multiplied by `multiplier`.
    public let initialDelay: Duration

    /// Factor by which the delay grows on each retry.
    public let multiplier: Double

    private let logger = Logger.forType(subsystem: "ShipItSwifty", RetryPolicy.self)

    /// Creates a `RetryPolicy`.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (including the first). Defaults to 3.
    ///   - initialDelay: Delay before the first retry. Defaults to 1 second.
    ///   - multiplier: Exponential growth factor. Defaults to 2.0.
    public init(
        maxAttempts: Int = 3,
        initialDelay: Duration = .seconds(1),
        multiplier: Double = 2.0
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
    }

    /// Execute an async operation with automatic retry on failure.
    ///
    /// - Parameter operation: The async throwing operation to execute.
    /// - Returns: The result of the operation on success.
    /// - Throws: The last error encountered after all attempts are exhausted.
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: any Error
        var currentDelay = initialDelay
        var attempt = 0

        repeat {
            do {
                if attempt > 0 {
                    logger.debug("Retry attempt \(attempt) of \(maxAttempts - 1), waiting \(currentDelay)")
                    try await Task.sleep(for: currentDelay)
                    currentDelay = Duration.seconds(
                        Double(currentDelay.components.seconds) * multiplier
                    )
                }
                return try await operation()
            } catch {
                lastError = error
                attempt += 1
                logger.warning("Attempt \(attempt) failed: \(error.localizedDescription)")
            }
        } while attempt < maxAttempts

        logger.error("All \(maxAttempts) attempts failed. Last error: \(lastError.localizedDescription)")
        throw lastError
    }
}

import Foundation
import Logging

/// Manages infrastructure-level retry logic for test invocations across all platforms.
///
/// `InfrastructureRetryScheduler` wraps any async test operation and retries it when the
/// platform-specific `InfrastructureFailureClassifier` determines that a failure is transient.
/// It uses exponential backoff with jitter to avoid thundering-herd problems.
///
/// ## Design
///
/// ```
///  ┌─────────────────────────────────────────┐
///  │       InfrastructureRetryScheduler       │
///  │  ┌───────────┐    ┌──────────────────┐  │
///  │  │ RetryOpts │    │    Classifier    │  │
///  │  │ (config)  │    │ (platform impl) │  │
///  │  └───────────┘    └──────────────────┘  │
///  └─────────────────────────────────────────┘
///         │                    │
///     exponential          isRetryable(log:)
///     backoff + jitter
/// ```
///
/// ## Usage
/// ```swift
/// let scheduler = InfrastructureRetryScheduler(
///     options: retryOptions,
///     classifier: IOSInfrastructureClassifier()
/// )
/// let result = try await scheduler.execute(label: "iPhone 16 Pro") {
///     try await runXcodeBuild(...)
/// }
/// ```
public struct InfrastructureRetryScheduler: Sendable {

    /// Configuration for infrastructure retry behavior.
    ///
    /// This is the cross-platform version of the retry options. Each platform's test
    /// runner reads from the same `InfrastructureRetryOptions` in the Shipfile.
    public struct Options: Codable, Sendable, Equatable {
        /// Whether infrastructure retries are enabled.
        public var enabled: Bool?

        /// Maximum total attempts (including the first try). Default: 3.
        public var maxAttempts: Int?

        /// Delay in seconds before the first retry. Subsequent retries use
        /// exponential backoff with jitter. Default: 2.
        public var initialDelaySeconds: Double?

        /// Maximum delay cap in seconds. Backoff will not exceed this. Default: 60.
        public var maxDelaySeconds: Double?

        enum CodingKeys: String, CodingKey {
            case enabled
            case maxAttempts = "max_attempts"
            case initialDelaySeconds = "initial_delay_seconds"
            case maxDelaySeconds = "max_delay_seconds"
        }

        public init(
            enabled: Bool? = nil,
            maxAttempts: Int? = nil,
            initialDelaySeconds: Double? = nil,
            maxDelaySeconds: Double? = nil
        ) {
            self.enabled = enabled
            self.maxAttempts = maxAttempts
            self.initialDelaySeconds = initialDelaySeconds
            self.maxDelaySeconds = maxDelaySeconds
        }

        // MARK: Resolved values with defaults

        public var isEnabled: Bool { enabled ?? false }
        public var resolvedMaxAttempts: Int { max(maxAttempts ?? 3, 1) }
        public var resolvedInitialDelay: Duration {
            .milliseconds(Int((initialDelaySeconds ?? 2.0) * 1000))
        }
        public var resolvedMaxDelay: Duration {
            .milliseconds(Int((maxDelaySeconds ?? 60.0) * 1000))
        }
    }

    /// Describes a test execution failure with its log output for classification.
    public struct TestFailureContext: Sendable {
        /// Combined stdout+stderr from the test process.
        public let log: String

        /// The underlying error.
        public let underlyingError: any Error & Sendable

        public init(log: String, underlyingError: any Error & Sendable) {
            self.log = log
            self.underlyingError = underlyingError
        }
    }

    // MARK: - Properties

    private let options: Options
    private let classifier: any InfrastructureFailureClassifier
    private let logger: Logger

    // MARK: - Init

    /// Creates a scheduler with the given options and platform classifier.
    ///
    /// - Parameters:
    ///   - options: Retry configuration (attempts, delays, caps).
    ///   - classifier: Platform-specific failure classifier.
    public init(
        options: Options,
        classifier: any InfrastructureFailureClassifier
    ) {
        self.options = options
        self.classifier = classifier
        self.logger = Logger.forType(subsystem: "ShipItSwifty", InfrastructureRetryScheduler.self)
    }

    // MARK: - Execution

    /// Execute an operation with infrastructure retry protection.
    ///
    /// - Parameters:
    ///   - label: Human-readable label for logging (e.g., destination name, module).
    ///   - operation: The async operation that may throw. When it throws, the closure
    ///     must return a `TestFailureContext` via the error, or throw directly. The
    ///     scheduler catches the error and classifies it.
    ///   - extractContext: Closure that extracts a `TestFailureContext` from a caught error.
    ///     Return `nil` if the error cannot be classified (will not retry).
    /// - Returns: The result of the operation on success.
    /// - Throws: The last error encountered if all retries are exhausted or the failure is
    ///   not classified as infrastructure.
    public func execute<T: Sendable>(
        label: String,
        operation: @Sendable () async throws -> T,
        extractContext: @Sendable (any Error & Sendable) -> TestFailureContext?
    ) async throws -> T {
        guard options.isEnabled else {
            return try await operation()
        }

        let maxAttempts = options.resolvedMaxAttempts
        var attempt = 1
        var currentDelay = options.resolvedInitialDelay
        let maxDelay = options.resolvedMaxDelay

        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maxAttempts else {
                    logger.error(
                        "[\(classifier.platformName)] All \(maxAttempts) attempts exhausted for '\(label)'. Failing."
                    )
                    throw error
                }

                guard let context = extractContext(error) else {
                    // Cannot classify — not retryable
                    throw error
                }

                guard classifier.isRetryable(log: context.log) else {
                    // Real failure, not infrastructure — do not retry
                    logger.debug(
                        "[\(classifier.platformName)] Failure on '\(label)' is not infrastructure-related. Not retrying."
                    )
                    throw error
                }

                // Infrastructure failure — retry with backoff + jitter
                let jitteredDelay = Self.applyJitter(to: currentDelay)
                logger.warning(
                    "[\(classifier.platformName)] Transient infrastructure failure on '\(label)'. Retrying attempt \(attempt + 1)/\(maxAttempts) after \(jitteredDelay)."
                )

                try await Task.sleep(for: jitteredDelay)

                // Advance backoff: double with cap
                currentDelay = Self.nextDelay(current: currentDelay, cap: maxDelay)
                attempt += 1
            }
        }
    }

    // MARK: - Backoff

    /// Doubles the delay, capped at the maximum.
    static func nextDelay(current: Duration, cap: Duration) -> Duration {
        let doubled = current * 2
        return doubled < cap ? doubled : cap
    }

    /// Applies ±25% jitter to a delay to decorrelate parallel retries.
    static func applyJitter(to delay: Duration) -> Duration {
        let seconds = Double(delay.components.seconds)
            + Double(delay.components.attoseconds) / 1_000_000_000_000_000_000
        // Jitter factor: random between 0.75 and 1.25
        let jitter = Double.random(in: 0.75...1.25)
        let jittered = seconds * jitter
        return .milliseconds(Int(jittered * 1000))
    }
}

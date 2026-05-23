import Foundation

// MARK: - Protocol

/// Classifies whether a test failure log represents a transient infrastructure problem
/// (retryable) versus a real test/build failure (not retryable).
///
/// Each platform implements its own classifier with patterns specific to its toolchain.
public protocol InfrastructureFailureClassifier: Sendable {
    /// The platform identifier for logging/diagnostics.
    var platformName: String { get }

    /// Returns `true` if the combined log output indicates a transient infrastructure
    /// failure that is safe to retry.
    func isRetryable(log: String) -> Bool
}

// MARK: - iOS Classifier

/// Classifies iOS/macOS xcodebuild infrastructure failures.
///
/// Retryable patterns include simulator boot failures, xctrunner launch crashes,
/// FBSOpenApplicationServiceErrorDomain errors, and CoreSimulator database locks.
public struct IOSInfrastructureClassifier: InfrastructureFailureClassifier {
    public let platformName = "iOS"

    public init() {}

    /// Known transient iOS infrastructure failure patterns.
    ///
    /// These are lowercased for case-insensitive matching against the combined
    /// stdout+stderr log from `xcodebuild test`.
    static let retryablePatterns: [String] = [
        "failed to launch app with identifier",
        "simulator device failed to launch",
        "the process failed to launch",
        "fbsopenapplicationserviceerrordomain",
        "failed to launch xctrunner",
        "unable to find xctrunner",
        "xctrunner.app exited",
        "xctrunner failed to launch",
        "database is locked",
        "testing cancelled because the build failed",
        "launch services error",
        "coresimulator timed out",
        "failed to start launchd_sim",
    ]

    /// Patterns that indicate a real failure — never retry these even if
    /// an infrastructure pattern also matches.
    static let nonRetryablePatterns: [String] = [
        "compile error",
        "linker command failed",
        "no signing certificate",
        "provisioning profile",
        "unable to find a destination matching",
        "the scheme",
        "xcodebuild: error: unable to find a",
    ]

    public func isRetryable(log: String) -> Bool {
        let normalized = log.lowercased()

        // If any non-retryable pattern is present, never retry
        for pattern in Self.nonRetryablePatterns where normalized.contains(pattern) {
            return false
        }

        // Check for retryable infrastructure patterns
        for pattern in Self.retryablePatterns where normalized.contains(pattern) {
            return true
        }

        return false
    }
}

// MARK: - Android Classifier

/// Classifies Android Gradle/emulator infrastructure failures.
///
/// Retryable patterns include emulator boot timeouts, ADB connection drops,
/// Gradle daemon crashes, and device-offline errors during instrumented tests.
public struct AndroidInfrastructureClassifier: InfrastructureFailureClassifier {
    public let platformName = "Android"

    public init() {}

    static let retryablePatterns: [String] = [
        "device not found",
        "device offline",
        "emulator-",  // e.g. "emulator-5554 device not found"
        "adb server didn't ack",
        "error: adb connection reset",
        "could not connect to adb",
        "failed to install apk",
        "install_failed_insufficient_storage",
        "install timed out",
        "gradle daemon disappeared",
        "gradle daemon was busy",
        "could not create service of type",
        "java.io.ioexception: connection reset",
        "java.net.connectexception: connection refused",
        "no connected devices",
        "test framework quit unexpectedly",
        "instrumentationresultparser timed out",
        "process crashed",
        "junit runner disconnected",
    ]

    static let nonRetryablePatterns: [String] = [
        "compilation failed",
        "could not resolve",
        "execution failed for task",
        "build failed with an exception",
        "> configure project",
    ]

    public func isRetryable(log: String) -> Bool {
        let normalized = log.lowercased()

        for pattern in Self.nonRetryablePatterns where normalized.contains(pattern) {
            return false
        }

        for pattern in Self.retryablePatterns where normalized.contains(pattern) {
            return true
        }

        return false
    }
}

// MARK: - Flutter Classifier

/// Classifies Flutter test infrastructure failures.
///
/// Retryable patterns include Flutter tool crashes, pub cache corruption,
/// and device connection timeouts.
public struct FlutterInfrastructureClassifier: InfrastructureFailureClassifier {
    public let platformName = "Flutter"

    public init() {}

    static let retryablePatterns: [String] = [
        "flutter tool crashed",
        "the flutter tool cannot access the file",
        "pub get failed",
        "could not resolve",  // pub dependency resolution timeout
        "connection closed before full header was received",
        "socketexception",
        "handshake exception",
        "timed out waiting for device",
        "device connection timeout",
        "observatory connection closed",
        "vm service connection closed",
        "flutter daemon crashed",
        "error connecting to the service protocol",
    ]

    static let nonRetryablePatterns: [String] = [
        "compiler error",
        "analysis issue",
        "dart analysis found",
        "error: target of uri doesn't exist",
        "couldn't find constructor",
    ]

    public func isRetryable(log: String) -> Bool {
        let normalized = log.lowercased()

        for pattern in Self.nonRetryablePatterns where normalized.contains(pattern) {
            return false
        }

        for pattern in Self.retryablePatterns where normalized.contains(pattern) {
            return true
        }

        return false
    }
}

// MARK: - React Native / JS Classifier

/// Classifies React Native (Jest/Mocha) infrastructure failures.
///
/// Retryable patterns include Metro bundler crashes, out-of-memory kills,
/// and worker pool exhaustion.
public struct ReactNativeInfrastructureClassifier: InfrastructureFailureClassifier {
    public let platformName = "ReactNative"

    public init() {}

    static let retryablePatterns: [String] = [
        "jest worker encountered",
        "worker process has failed to exit gracefully",
        "out of memory",
        "javascript heap out of memory",
        "enospc",  // file watcher limit
        "metro bundler process exited",
        "unable to connect to the metro server",
        "connection refused",
        "epipe",
        "emfile",  // too many open files
        "sigkill",
        "exited with non-zero code: null",
        "test suite failed to run",  // Jest infra error (not assertion)
    ]

    static let nonRetryablePatterns: [String] = [
        "syntaxerror",
        "referenceerror",
        "typeerror",
        "cannot find module",
        "module not found",
    ]

    public func isRetryable(log: String) -> Bool {
        let normalized = log.lowercased()

        for pattern in Self.nonRetryablePatterns where normalized.contains(pattern) {
            return false
        }

        for pattern in Self.retryablePatterns where normalized.contains(pattern) {
            return true
        }

        return false
    }
}

// MARK: - KMP Classifier

/// Classifies Kotlin Multiplatform iOS test infrastructure failures run via Gradle.
///
/// Combines iOS simulator patterns with Gradle daemon patterns since KMP iOS tests
/// invoke the simulator through Gradle.
public struct KMPInfrastructureClassifier: InfrastructureFailureClassifier {
    public let platformName = "KMP"

    private let iosClassifier = IOSInfrastructureClassifier()
    private let androidClassifier = AndroidInfrastructureClassifier()

    public init() {}

    /// Additional KMP-specific patterns beyond what iOS/Android cover.
    static let retryablePatterns: [String] = [
        "could not connect to konan compiler daemon",
        "kotlin/native compiler daemon is not responding",
        "execution failed for task ':shared:linkdebugtest",
    ]

    static let nonRetryablePatterns: [String] = [
        "unresolved reference",
        "type mismatch",
        "e: file:",
    ]

    public func isRetryable(log: String) -> Bool {
        let normalized = log.lowercased()

        for pattern in Self.nonRetryablePatterns where normalized.contains(pattern) {
            return false
        }

        for pattern in Self.retryablePatterns where normalized.contains(pattern) {
            return true
        }

        // Delegate to iOS classifier (for simulator patterns) and Android (for Gradle daemon)
        return iosClassifier.isRetryable(log: log)
            || androidClassifier.isRetryable(log: log)
    }
}

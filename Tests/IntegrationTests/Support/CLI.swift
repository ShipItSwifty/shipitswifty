import Foundation
import Testing

/// Result of running the `shipit` CLI subprocess.
struct CLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    /// Combined output (stdout + stderr) for diagnostics.
    var output: String { [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// Subprocess harness for running the compiled `shipit` binary in integration tests.
///
/// Requires the binary to be pre-built:
/// ```
/// swift build
/// swift test --filter IntegrationTests
/// ```
/// Or override the binary path via the `SHIPIT_BINARY_PATH` environment variable.
enum CLI {

    // MARK: - Binary path resolution

    private static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support/
        .deletingLastPathComponent()  // IntegrationTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // package root

    static var binaryPath: String {
        if let override = ProcessInfo.processInfo.environment["SHIPIT_BINARY_PATH"] {
            return override
        }
        // Prefer debug build; fall back to release.
        let debug = packageRoot.appendingPathComponent(".build/debug/shipit").path
        let release = packageRoot.appendingPathComponent(".build/release/shipit").path
        if FileManager.default.fileExists(atPath: debug) { return debug }
        if FileManager.default.fileExists(atPath: release) { return release }
        return debug  // will fail at launch time with a clear error
    }

    // MARK: - Run

    /// Run `shipit` with the given arguments.
    ///
    /// - Parameters:
    ///   - arguments: CLI arguments (e.g. `["build", "--dry-run"]`).
    ///   - workingDirectory: Directory to run in. Defaults to a temp directory.
    ///   - environment: Additional environment variables merged over the current process env.
    ///   - timeout: Maximum execution time in seconds. Default: 120.
    static func run(
        _ arguments: String...,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> CLIResult {
        try await run(
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout
        )
    }

    static func run(
        _ arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> CLIResult {
        let binary = binaryPath
        guard FileManager.default.fileExists(atPath: binary) else {
            throw CLIHarnessError.binaryNotFound(
                path: binary,
                hint: "Run `swift build` before running IntegrationTests"
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let runner = ProcessRunner(
                binaryPath: binary,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                timeout: timeout
            )
            runner.launch { result in
                continuation.resume(with: result)
            }
        }
    }
}

// MARK: - ProcessRunner

/// Thread-safe box for captured output data from pipe readers.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()
    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }
    func append(_ d: Data) {
        lock.lock()
        defer { lock.unlock() }
        _data.append(d)
    }
}

/// Thread-safe timeout state shared between the process timer and termination handler.
private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var didTimeOut = false

    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        didTimeOut = true
    }

    func timedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }
}

/// Wraps `Process` in a `@unchecked Sendable` class so it can cross actor boundaries.
private final class ProcessRunner: @unchecked Sendable {

    private let binaryPath: String
    private let arguments: [String]
    private let workingDirectory: URL?
    private let environment: [String: String]?
    private let timeout: TimeInterval

    init(
        binaryPath: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        timeout: TimeInterval
    ) {
        self.binaryPath = binaryPath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }

    func launch(completion: @escaping @Sendable (Result<CLIResult, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        if let dir = workingDirectory {
            process.currentDirectoryURL = dir
        }

        var env = ProcessInfo.processInfo.environment
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read pipes on background threads to avoid pipe-buffer deadlock.
        // A pipe buffer is ~64 KB on macOS; commands like `schema` emit >100 KB.
        // If we only read in terminationHandler the child blocks trying to write,
        // so it never exits, so the handler never fires — classic deadlock.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()
        let timeoutState = TimeoutState()

        group.enter()
        DispatchQueue.global().async {
            stdoutBox.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            stderrBox.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            timeoutState.markTimedOut()
            process.terminate()
        }

        process.terminationHandler = { p in
            let status = p.terminationStatus
            group.notify(queue: .global()) {
                let stdout = String(data: stdoutBox.data, encoding: .utf8) ?? ""
                let stderr = String(data: stderrBox.data, encoding: .utf8) ?? ""
                if timeoutState.timedOut() {
                    completion(.failure(CLIHarnessError.timedOut(timeout: self.timeout, command: [self.binaryPath] + self.arguments)))
                } else {
                    completion(
                        .success(
                            CLIResult(
                                stdout: stdout,
                                stderr: stderr,
                                exitCode: status
                            )))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - Errors

enum CLIHarnessError: Error, CustomStringConvertible, Sendable {
    case binaryNotFound(path: String, hint: String)
    case timedOut(timeout: TimeInterval, command: [String])

    var description: String {
        switch self {
        case .binaryNotFound(let path, let hint):
            return "shipit binary not found at '\(path)'. \(hint)"
        case .timedOut(let timeout, let command):
            return "shipit command timed out after \(Int(timeout))s: \(command.joined(separator: " "))"
        }
    }
}

import Foundation
import Testing

// MARK: - E2E tags
//
// Tiers let you slice the e2e suites (all opt-in so a plain run stays fast):
//   SHIPIT_E2E=1       swift test --filter IntegrationTests   # quick tier (test + lint)
//   SHIPIT_E2E_BUILD=1 swift test --filter IntegrationTests   # + build tier
//   SHIPIT_E2E_FULL=1  swift test --filter IntegrationTests   # + full tier (archive/signing)

extension Tag {
    /// Fast real-toolchain checks: `shipit test` + `shipit lint`.
    @Tag static var e2eQuick: Self
    /// Real `shipit build`/`archive` runs that confirm the fixtures actually compile.
    @Tag static var e2eBuild: Self
    /// Full release pipeline: archive, code signing, validate signing, downstream steps.
    @Tag static var e2eFull: Self
}

// MARK: - Bootstrap helpers
//
// Vendored fixtures are committed source-only. Dependencies are regenerated into the
// per-test temp copy (from `withFixtureCopy`) before invoking `shipit`.

/// `flutter pub get` in the given Flutter project copy.
@discardableResult
func bootstrapFlutter(in project: URL, timeout: TimeInterval = 600) async throws -> ToolResult {
    try await runTool("flutter", ["pub", "get"], in: project, timeout: timeout)
}

/// `npm install` in the given React Native project copy (regenerates `node_modules`).
@discardableResult
func bootstrapReactNativeNode(in project: URL, timeout: TimeInterval = 900) async throws -> ToolResult {
    try await runTool("npm", ["install", "--no-audit", "--no-fund"], in: project, timeout: timeout)
}

/// Installs CocoaPods dependencies for the RN iOS project copy (build/full tiers only).
///
/// Prefers the project's pinned CocoaPods via Bundler (`bundle exec pod install`); falls
/// back to a system `pod install`. `node_modules` must already be bootstrapped because RN
/// podspecs resolve through it.
@discardableResult
func bootstrapReactNativePods(in project: URL, timeout: TimeInterval = 1800) async throws -> ToolResult {
    let iosDir = project.appendingPathComponent("ios")
    let hasGemfile = FileManager.default.fileExists(atPath: project.appendingPathComponent("Gemfile").path)
    if hasGemfile {
        let bundleInstall = try await runTool("bundle", ["install"], in: project, timeout: timeout)
        if bundleInstall.succeeded {
            return try await runTool("bundle", ["exec", "pod", "install"], in: iosDir, timeout: timeout)
        }
    }
    return try await runTool("pod", ["install"], in: iosDir, timeout: timeout)
}

// MARK: - Timing

/// Runs `body`, prints the elapsed wall-clock time with `label`, and returns the result.
/// Used by the build tier so we can see how long real Flutter/RN builds take.
@discardableResult
func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
    let start = Date()
    defer {
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "⏱  [e2e] %@ took %.1fs", label, elapsed))
    }
    return try await body()
}

// MARK: - Generic tool runner

struct ToolResult: Sendable {
    let exitCode: Int32
    let output: String
    var succeeded: Bool { exitCode == 0 }
}

/// Runs an arbitrary tool on PATH (e.g. `flutter`, `npm`, `pod`, `bundle`) in `directory`,
/// capturing combined stdout+stderr. Reads pipes on a background thread to avoid buffer deadlock.
///
/// Test-only helper — production code must route shell execution through SwiftyShell.
@discardableResult
func runTool(
    _ tool: String,
    _ arguments: [String],
    in directory: URL,
    environment: [String: String]? = nil,
    timeout: TimeInterval = 600
) async throws -> ToolResult {
    try await withCheckedThrowingContinuation { continuation in
        let runner = ToolProcessRunner(
            tool: tool,
            arguments: arguments,
            directory: directory,
            environment: environment,
            timeout: timeout
        )
        runner.launch { continuation.resume(with: $0) }
    }
}

private final class ToolOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()
    var string: String { lock.lock(); defer { lock.unlock() }; return String(data: _data, encoding: .utf8) ?? "" }
    func append(_ d: Data) { lock.lock(); defer { lock.unlock() }; _data.append(d) }
}

private final class ToolProcessRunner: @unchecked Sendable {
    private let tool: String
    private let arguments: [String]
    private let directory: URL
    private let environment: [String: String]?
    private let timeout: TimeInterval

    init(tool: String, arguments: [String], directory: URL, environment: [String: String]?, timeout: TimeInterval) {
        self.tool = tool
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.timeout = timeout
    }

    func launch(completion: @escaping @Sendable (Result<ToolResult, Error>) -> Void) {
        let process = Process()
        // Resolve the tool on PATH via /usr/bin/env so shims (nodenv, etc.) work.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.currentDirectoryURL = directory

        var env = ProcessInfo.processInfo.environment
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe  // merge for simple diagnostics

        let box = ToolOutputBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            box.append(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        let timedOut = TimeoutFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
        }

        process.terminationHandler = { p in
            let status = p.terminationStatus
            group.notify(queue: .global()) {
                if timedOut.value {
                    completion(.failure(BootstrapError.timedOut(tool: self.tool, timeout: self.timeout)))
                } else {
                    completion(.success(ToolResult(exitCode: status, output: box.string)))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(BootstrapError.launchFailed(tool: tool, underlying: error)))
        }
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
    func set() { lock.lock(); defer { lock.unlock() }; _value = true }
}

enum BootstrapError: Error, CustomStringConvertible, Sendable {
    case timedOut(tool: String, timeout: TimeInterval)
    case launchFailed(tool: String, underlying: Error)

    var description: String {
        switch self {
        case .timedOut(let tool, let timeout):
            return "`\(tool)` bootstrap timed out after \(Int(timeout))s"
        case .launchFailed(let tool, let underlying):
            return "Failed to launch `\(tool)`: \(underlying)"
        }
    }
}

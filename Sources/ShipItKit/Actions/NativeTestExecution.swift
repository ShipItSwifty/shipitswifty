#if os(macOS)
import Foundation
import MobileBuild
import MobileTesting
import SwiftyShell
import XcodeBuildKit
import XcrunKit

/// Sequential native test orchestration. The products survive every execution attempt.
struct NativeTestExecution: Sendable {
    let action: TestAction
    let context: ActionContext

    func run(options: TestAction.Options) async throws -> TestAction.Result {
        guard options.testPlan == nil || options.testPlans == nil else {
            throw ShipItError.invalidConfiguration(reason: "Use test_plan or test_plans, not both")
        }
        guard let scheme = options.scheme ?? context.config.appScheme else {
            throw ShipItError.invalidConfiguration(reason: "Test requires a scheme")
        }
        let plans: [String?] = options.testPlans.map { $0.map(Optional.some) } ?? [options.testPlan]
        guard !plans.isEmpty, plans.compactMap({ $0 }).allSatisfy({ !$0.isEmpty }) else {
            throw ShipItError.invalidConfiguration(reason: "test_plans must not be empty")
        }
        try validatePlans(plans.compactMap { $0 })
        let destinations: [String]
        if let supplied = options.resolvedDestinations {
            destinations = supplied
        } else {
            destinations = [try await action.autoDiscoverDestination(scheme: scheme, context: context)]
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: options.testProductsPath ?? "build/test-runs").deletingLastPathComponent(),
            withIntermediateDirectories: true)
        guard !destinations.isEmpty else { throw ShipItError.invalidConfiguration(reason: "At least one destination is required") }
        guard Set(destinations.map { $0.contains("Simulator") ? "simulator" : "device" }).count == 1 else {
            throw ShipItError.invalidConfiguration(reason: "Simulator and physical-device tests require separate shared builds")
        }
        let root = URL(
            fileURLWithPath: (context.evidenceRoot.map { $0 + "/test-runs/" } ?? "build/test-runs/") + "xcode-\(UUID().uuidString)"
        ).standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let products = options.testProductsPath ?? root.appendingPathComponent("tests.xctestproducts").path
        if FileManager.default.fileExists(atPath: products) {
            throw ShipItError.invalidConfiguration(reason: "test_products_path already exists: \(products)")
        }
        let container: XcodeContainer?
        if let workspace = context.config.appWorkspace {
            container = .workspace(workspace)
        } else if let project = context.config.appProject {
            container = .project(project)
        } else {
            container = nil
        }
        var additionalOptions: [XcodeBuildOption] = []
        if options.skipMacroValidation == true { additionalOptions.append(.skipMacroValidation) }
        if options.enableCodeCoverage == true { additionalOptions.append(.enableCodeCoverage("YES")) }
        let buildRequest = XcodeBuildRequest(
            container: container,
            scheme: scheme,
            configuration: options.configuration ?? "Debug",
            destination: .custom(destinations[0]),
            buildSettings: context.config.xcargs,
            additionalOptions: additionalOptions
        )
        let builder = XcodeBuilder(shell: context.shell, output: context.buildOutput)
        let runner = XcodeTestRunner(shell: context.shell, output: context.buildOutput)
        // Known before anything runs, so a report written by an early failure still says where the tests were headed.
        var reportDestinations: [TestDestination] = destinations.flatMap { destination in
            plans.map { TestDestination.xcode(specifier: destination, plan: $0) }
        }
        let buildDirectory = root.appendingPathComponent("build")
        let buildStarted = Date()
        let build: ShellOutput
        let buildArguments: [String]
        do {
            let outcome = try await builder.buildForTesting(buildRequest, testProductsPath: products)
            build = outcome.output
            buildArguments = Array(
                builder.command(for: buildRequest).option(.testProductsPath(products)).buildForTesting().command().arguments)
            for note in outcome.diagnostics { context.logger.warning("\(note)") }
        } catch let failure as BuildFailure {
            build = failure.output
            buildArguments = Array(failure.command.dropFirst())
        } catch {
            try? FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
            try? saveInterruptedTestOutput(error, directory: buildDirectory)
            throw error
        }
        let buildSeconds = Date().timeIntervalSince(buildStarted)
        recordLogs(build, arguments: buildArguments, started: buildStarted, seconds: buildSeconds, directory: buildDirectory)
        if build.exitCode != 0 {
            let failure = TestRunReport(
                runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: root.path,
                destinations: reportDestinations, buildSeconds: buildSeconds,
                attempts: [.init(attemptNumber: 1, reason: "build", summary: .init(errored: 1), failedTests: [], source: root.path)],
                summary: .init(errored: 1))
            saveEvidence("build failure report", logger: context.logger) {
                try writeJSON(failure, to: URL(fileURLWithPath: options.reportPath ?? root.appendingPathComponent("report.json").path))
            }
            throw ShipItError.testFailed(exitCode: Int(build.exitCode), failureCount: 0, log: build.stdout + build.stderr)
        }
        var serialDestinations = Set<String>()
        var attempts: [TestAttempt] = []
        var initialFailures: [ParsedTestCase] = []
        var initialCases: [ParsedTestCase] = []
        var remainingAll: [ParsedTestCase] = []
        var flaky: [ParsedTestCase] = []
        var passed = 0
        var skipped = 0
        var errored = 0
        var resultPaths: [String] = []
        var owned: [String] = []
        var leases: [SimulatorLease] = []
        var leasedDevices = Set<String>()
        do {
            for (destinationIndex, destination) in destinations.enumerated() {
                let udid = try await action.resolveSimulatorUDID(scheme: scheme, destination: destination, context: context)
                if let udid, !leasedDevices.contains(udid), (try? await simulatorState(udid)) != nil {
                    leases.append(try await SimulatorLease.acquire(device: udid, shell: context.shell))
                    leasedDevices.insert(udid)
                }
                if let udid, options.eraseSimulator == true {
                    let state = try await simulatorState(udid)
                    guard state != "Booted" else {
                        throw ShipItError.invalidConfiguration(reason: "Refusing to erase an already booted simulator: \(udid)")
                    }
                    _ = try await Simctl(context: context.shell).erase([udid]).run()
                }
                if let udid, let state = try? await simulatorState(udid), state == "Shutdown" {
                    _ = try await Simctl(context: context.shell).boot(udid).run()
                    owned.append(udid)
                    _ = try await Simctl(context: context.shell).bootStatus(udid).run()
                }
                for (planIndex, plan) in plans.enumerated() {
                    let planConfigurations = try planSettings(plan)
                    // One destination per plan on each Xcode destination: the environment plus the plan it ran.
                    var placed = TestDestination.xcode(specifier: destination, plan: plan)
                    var resolvedName: String?
                    var number = 1
                    var infrastructureAttempts = 1
                    var rerunAttempts = 1
                    var fellBack = false
                    var retryDelay = options.infrastructureRetry?.resolvedInitialDelay ?? .zero
                    var reason = "initial"
                    var first: ParsedTestRun?
                    var remaining: [ParsedTestCase] = []
                    var selectors: [String]? = nil
                    var configurations: [String] = []
                    while true {
                        try Task.checkCancellation()
                        let directory = root.appendingPathComponent(
                            "plan-\(planIndex + 1)/destination-\(destinationIndex + 1)/attempt-\(number)")
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let resultPath: String
                        if number == 1, plans.count == 1, destinations.count == 1, let explicit = options.resultBundlePath {
                            // Preserve the historical explicit-path behavior only for the initial run.
                            if FileManager.default.fileExists(atPath: explicit) { try FileManager.default.removeItem(atPath: explicit) }
                            resultPath = explicit
                        } else {
                            resultPath = directory.appendingPathComponent("results.xcresult").path
                        }
                        // On a failing test xcodebuild otherwise gathers a simulator sysdiagnose, which can hang for its
                        // full 600s timeout after the tests finished in under a second. ShipIt keeps its own device log,
                        // screenshot and result-bundle attachments for every attempt, so the sysdiagnose adds nothing.
                        var extraOptions: [XcodeBuildOption] = [.collectTestDiagnostics("never")]
                        let serial = options.serial == true || serialDestinations.contains(destination)
                        if serial { extraOptions.append(.parallelTestingEnabled("NO")) }
                        if options.retryOnFailure == true { extraOptions.append(.retryTestsOnFailure) }
                        let selection = XcodeTestSelection(
                            testPlan: plan, onlyTesting: selectors ?? options.onlyTesting ?? [], skipTesting: options.skipTesting ?? [],
                            onlyTestConfigurations: configurations)
                        try await action.resetIOSAppInstallationIfNeeded(scheme: scheme, destination: destination, context: context)
                        let attemptStarted = Date()
                        let output: ShellOutput
                        let run: ParsedTestRun
                        let testSeconds: TimeInterval
                        let arguments: [String]
                        do {
                            let execution = try await runner.testWithoutBuilding(
                                testProducts: products, destination: .custom(destination), selection: selection,
                                resultBundlePath: resultPath, additionalOptions: extraOptions)
                            (output, run, testSeconds, arguments) = (
                                execution.output, execution.run, execution.durationSeconds, Array(execution.command.dropFirst())
                            )
                        } catch let failure as TestExecutionFailure {
                            // Nothing usable came back (no result bundle, or one that cannot be read): an errored attempt.
                            context.logger.warning("Attempt \(number) of plan \(plan ?? "default"): \(failure.reason)")
                            (output, testSeconds, arguments) = (
                                failure.output, Date().timeIntervalSince(attemptStarted), Array(failure.command.dropFirst())
                            )
                            run = ParsedTestRun(
                                runner: .xcodebuild, framework: context.config.iosBuildSystem, source: resultPath,
                                summary: .init(errored: 1), diagnostics: [.init(severity: .error, message: failure.reason)])
                        } catch {
                            try? saveInterruptedTestOutput(error, directory: directory)
                            throw error
                        }
                        recordLogs(output, arguments: arguments, started: attemptStarted, seconds: testSeconds, directory: directory)
                        let log = output.stdout + output.stderr
                        // A UDID-only specifier names the device by an identifier that differs per machine; the result
                        // bundle knows its real name, so use that and keep IDs stable across machines.
                        if resolvedName == nil, run.destinations.count == 1, let name = run.destinations[0].name {
                            resolvedName = name
                            let renamed = TestDestination.xcode(specifier: destination, plan: plan, resolvedName: name)
                            if let index = reportDestinations.firstIndex(of: placed) { reportDestinations[index] = renamed }
                            placed = renamed
                        }
                        let scopedCases = run.testCases.map { test in
                            var metadata = test.metadata ?? [:]
                            metadata["plan"] = plan ?? "default"
                            metadata["destination"] = destination
                            if let udid { metadata["simulator_udid"] = udid }
                            if let configuration = metadata["configuration"], let settings = planConfigurations[configuration] {
                                metadata.merge(settings) { old, _ in old }
                            } else if planConfigurations.count == 1, let configuration = planConfigurations.first {
                                metadata["configuration"] = configuration.key
                                metadata.merge(configuration.value) { old, _ in old }
                            }
                            return test.copy(
                                stableID: "plan-\(planIndex + 1):destination-\(destinationIndex + 1):" + test.stableID,
                                metadata: metadata, destinationID: placed.id, attempts: .some(test.attempts ?? 1))
                        }
                        let failures = scopedCases.filter { $0.status == .failed || $0.status == .errored }
                        // Time in the test command itself, and everything around it (reinstalling the app, reading the
                        // result bundle), so a slow attempt can be told apart from a slow test.
                        let overheadSeconds = max(0, Date().timeIntervalSince(attemptStarted) - testSeconds)
                        context.logger.info(
                            "Attempt \(number) of plan \(plan ?? "default"): tests \(Self.format(testSeconds)), overhead \(Self.format(overheadSeconds))"
                        )
                        attempts.append(
                            .init(
                                attemptNumber: number, reason: reason,
                                metadata: [
                                    "plan": plan ?? "default", "destination": destination, "serial": String(serial),
                                    "exit_code": String(output.exitCode), "overhead_seconds": String(format: "%.1f", overheadSeconds),
                                ],
                                summary: run.summary, failedTests: failures, durationSeconds: testSeconds, source: resultPath))
                        resultPaths.append(resultPath)
                        saveEvidence("attempt results", logger: context.logger) {
                            try writeJSON(run, to: directory.appendingPathComponent("results.json"))
                        }
                        if FileManager.default.fileExists(atPath: resultPath) {
                            _ = try? await EvidenceExporter(shell: context.shell).export(
                                runs: [run], sources: [resultPath], to: directory.appendingPathComponent("evidence").path)
                        }
                        if output.exitCode != 0, let udid { await captureDeviceFailure(udid, directory: directory) }
                        let kind = IOSInfrastructureClassifier().failureKind(log: log)
                        if output.exitCode != 0, kind == .clone, !serial, !fellBack {
                            fellBack = true
                            serialDestinations.insert(destination)
                            reason = "serial_fallback"
                            number += 1
                            context.logger.warning(
                                "Simulator cloning failed; retrying plan \(plan ?? "default") serially without rebuilding")
                            continue
                        }
                        if output.exitCode != 0, kind == .missingRuntime {
                            let runtimes = try? await Simctl(context: context.shell).list(.runtimes, json: true).run()
                            saveEvidence("runtime list", logger: context.logger) {
                                try (runtimes?.stdout ?? "Runtime list unavailable").write(
                                    to: directory.appendingPathComponent("runtimes.json"), atomically: true, encoding: .utf8)
                            }
                        }
                        if output.exitCode != 0, kind == .transient, let policy = options.infrastructureRetry,
                            infrastructureAttempts < policy.resolvedMaxAttempts
                        {
                            infrastructureAttempts += 1
                            number += 1
                            reason = "infrastructure"
                            try await Task.sleep(for: InfrastructureRetryScheduler.applyJitter(to: retryDelay))
                            retryDelay = InfrastructureRetryScheduler.nextDelay(current: retryDelay, cap: policy.resolvedMaxDelay)
                            continue
                        }
                        if first == nil {
                            first = run
                            remaining = failures
                            initialFailures += failures
                            initialCases += scopedCases
                        } else {
                            let recovered = Set(scopedCases.filter { $0.status == .passed }.map(\.stableID))
                            flaky += remaining.filter { recovered.contains($0.stableID) }
                            remaining = remaining.filter { !recovered.contains($0.stableID) }
                            for failure in failures where !remaining.contains(where: { $0.stableID == failure.stableID }) {
                                remaining.append(failure)
                            }
                        }
                        if (output.exitCode != 0 || run.summary.errored > 0
                            || run.summary.passed + run.summary.failed + run.summary.skipped == 0) && failures.isEmpty
                        {
                            errored += 1
                            break
                        }
                        if !remaining.isEmpty, options.rerunFailedTests?.enabled == true,
                            rerunAttempts < max(1, options.rerunFailedTests?.maxAttempts ?? 2)
                        {
                            let planned = remaining.compactMap { test -> String? in
                                guard case .xcodeOnlyTesting(let value) = test.rerunSelector else { return nil }
                                return value
                            }
                            if !planned.isEmpty {
                                selectors = Array(Set(planned)).sorted()
                                configurations = Array(Set(remaining.compactMap { $0.metadata?["configuration"] })).sorted()
                                rerunAttempts += 1
                                number += 1
                                reason = "failed_tests"
                                continue
                            }
                        }
                        break
                    }
                    passed += first?.summary.passed ?? 0
                    skipped += first?.summary.skipped ?? 0
                    remainingAll += remaining
                }
            }
        } catch {
            await teardown(owned)
            leases.forEach { $0.release() }
            try? writeJSON(attempts, to: root.appendingPathComponent("attempts.json"))
            let recovered = Set(flaky.map(\.stableID))
            var outstanding = initialFailures.filter { !recovered.contains($0.stableID) }
            for failure in remainingAll where !outstanding.contains(where: { $0.stableID == failure.stableID }) {
                outstanding.append(failure)
            }
            let report = TestRunReport(
                runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: root.path, destinations: reportDestinations,
                buildSeconds: buildSeconds,
                attempts: attempts, initialFailedTests: initialFailures,
                flakyTests: flaky, persistentFailedTests: outstanding,
                summary: .init(
                    passed: initialCases.filter { $0.status == .passed }.count + flaky.count,
                    failed: outstanding.filter { $0.status == .failed }.count,
                    skipped: initialCases.filter { $0.status == .skipped }.count, flaky: flaky.count,
                    errored: max(1, errored) + outstanding.filter { $0.status == .errored }.count),
                testCases: finalTestCases(initialCases, remaining: outstanding, flaky: flaky, attempts: attempts)
            ).unifyingFlaky()
            try? writeJSON(report, to: root.appendingPathComponent("report.json"))
            if let path = options.reportPath { try? writeJSON(report, to: URL(fileURLWithPath: path)) }
            throw error
        }
        await teardown(owned)
        leases.forEach { $0.release() }
        let report = TestRunReport(
            runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: root.path, destinations: reportDestinations,
            buildSeconds: buildSeconds,
            attempts: attempts, initialFailedTests: initialFailures, flakyTests: flaky, persistentFailedTests: remainingAll,
            summary: .init(
                passed: passed + flaky.count, failed: remainingAll.filter { $0.status == .failed }.count,
                skipped: skipped, flaky: flaky.count, errored: errored + remainingAll.filter { $0.status == .errored }.count),
            testCases: finalTestCases(initialCases, remaining: remainingAll, flaky: flaky, attempts: attempts)
        ).unifyingFlaky()
        saveEvidence("report", logger: context.logger) { try writeJSON(report, to: root.appendingPathComponent("report.json")) }
        // A requested report path is part of the result: surface a write failure only when the tests passed, so it
        // can never hide a test failure.
        let failed = report.summary.failed + report.summary.errored > 0
        if let path = options.reportPath {
            if failed {
                saveEvidence("requested report", logger: context.logger) { try writeJSON(report, to: URL(fileURLWithPath: path)) }
            } else {
                try writeJSON(report, to: URL(fileURLWithPath: path))
            }
        }
        if failed {
            throw ShipItError.testFailed(
                exitCode: 65, failureCount: report.summary.failed + report.summary.errored, log: "See \(root.path)/report.json")
        }
        return .init(
            passCount: report.summary.passed, failCount: 0, skipCount: report.summary.skipped,
            resultBundlePath: resultPaths.first, report: report)
    }
    private func planSettings(_ plan: String?) throws -> [String: [String: String]] {
        guard let plan else { return [:] }
        let root =
            context.config.appProject.map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: context.config.projectRoot, isDirectory: true))
                    .standardizedFileURL.deletingLastPathComponent()
            } ?? URL(fileURLWithPath: context.config.projectRoot)
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL]
            ?? []
        guard
            let file = files.first(where: {
                $0.pathExtension == "xctestplan" && $0.deletingPathExtension().lastPathComponent == plan && !$0.path.contains("/build/")
            })
        else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        var configurations: [String: [String: String]] = [:]
        for configuration in object?["configurations"] as? [[String: Any]] ?? [] {
            guard let name = configuration["name"] as? String else { continue }
            let options = configuration["options"] as? [String: Any] ?? [:]
            configurations[name] = ["language": options["language"] as? String, "region": options["region"] as? String].compactMapValues {
                $0
            }
        }
        return configurations
    }

    private func validatePlans(_ plans: [String]) throws {
        guard plans.count > 1 else { return }
        let root =
            context.config.appProject.map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: context.config.projectRoot, isDirectory: true))
                    .standardizedFileURL.deletingLastPathComponent()
            } ?? URL(fileURLWithPath: context.config.projectRoot)
        let files =
            (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL]
            ?? []).filter { $0.pathExtension == "xctestplan" && !$0.path.contains("/build/") }
        var targets: Set<String>?
        for plan in plans {
            let matches = files.filter { $0.deletingPathExtension().lastPathComponent == plan }
            guard matches.count <= 1 else { throw ShipItError.invalidConfiguration(reason: "Ambiguous test plan name: \(plan)") }
            guard let file = matches.first else { continue }  // Xcode resolves scheme-managed plans outside the project root.
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let selected = Set(
                (object?["testTargets"] as? [[String: Any]] ?? []).filter { $0["enabled"] as? Bool != false }.compactMap {
                    item -> String? in
                    guard let target = item["target"] as? [String: Any] else { return nil }
                    return [target["containerPath"] as? String, target["identifier"] as? String, target["name"] as? String].compactMap {
                        $0
                    }.joined(separator: ":")
                })
            if let targets, targets != selected {
                throw ShipItError.invalidConfiguration(reason: "Plans with different test targets require separate test steps: \(plan)")
            }
            targets = selected
        }
    }

    /// Runs `command`, keeps its logs, and returns its output with how long it ran.
    private func recordLogs(_ output: ShellOutput, arguments: [String], started: Date, seconds: TimeInterval, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        saveEvidence("attempt logs", logger: context.logger) {
            try output.stdout.write(to: directory.appendingPathComponent("stdout.log"), atomically: true, encoding: .utf8)
            try output.stderr.write(to: directory.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)
            try writeJSON(
                CommandRecord(
                    arguments: arguments, exitCode: [String(output.exitCode)], startedAt: started, durationSeconds: seconds),
                to: directory.appendingPathComponent("command.json"))
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        seconds >= 60
            ? String(format: "%.0fm %02.0fs", (seconds / 60).rounded(.down), seconds.truncatingRemainder(dividingBy: 60))
            : String(format: "%.1fs", seconds)
    }
    private func simulatorState(_ udid: String) async throws -> String? {
        let output = try await Simctl(context: context.shell).list(.devices, json: true).run()
        guard let data = output.stdout.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = object["devices"] as? [String: [[String: Any]]]
        else { return nil }
        return devices.values.flatMap { $0 }.first { $0["udid"] as? String == udid }?["state"] as? String
    }
    private func teardown(_ owned: [String]) async {
        for udid in owned {
            do { _ = try await Simctl(context: context.shell).shutdown([udid]).timeout(.seconds(10)).run() } catch {
                context.logger.warning("Simulator cleanup failed for \(udid): \(error)")
            }
        }
    }
    private func captureDeviceFailure(_ udid: String, directory: URL) async {
        _ = try? await Simctl(context: context.shell).io(
            udid, command: "screenshot", arguments: [directory.appendingPathComponent("failure.png").path]
        ).timeout(.seconds(10)).run()
        let output = try? await Simctl(context: context.shell).spawn(
            udid, executable: "log", arguments: ["show", "--last", "1m", "--style", "compact"]
        ).timeout(.seconds(10)).run()
        try? (output?.stdout ?? "Device logs unavailable").write(
            to: directory.appendingPathComponent("device.log"), atomically: true, encoding: .utf8)
        try? writeJSON(
            ["orientation": "unknown", "app_running": "unknown", "device": udid, "capture": "after_attempt_failure"],
            to: directory.appendingPathComponent("device-state.json"))
    }
}
#endif

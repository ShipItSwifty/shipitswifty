#if os(macOS)
import Foundation
import SwiftyShell

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
        var base = context.streamingXcodeBuild().option(.scheme(scheme)).option(.configuration(options.configuration ?? "Debug"))
        if let workspace = context.config.appWorkspace {
            base = base.workspace(workspace)
        } else if let project = context.config.appProject {
            base = base.project(project)
        }
        for (key, value) in context.config.xcargs { base = base.buildSetting(key, value) }
        if options.skipMacroValidation == true { base = base.option(.skipMacroValidation) }
        if options.enableCodeCoverage == true { base = base.option(.enableCodeCoverage("YES")) }
        // Known before anything runs, so a report written by an early failure still says where the tests were headed.
        var reportDestinations: [TestDestination] = destinations.flatMap { destination in
            plans.map { TestDestination.xcode(specifier: destination, plan: $0) }
        }
        let build = try await capture(
            base.option(.destination(destinations[0])).option(.testProductsPath(products)).buildForTesting(),
            directory: root.appendingPathComponent("build"))
        if build.exitCode != 0 {
            let failure = TestRunReport(
                runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: root.path,
                destinations: reportDestinations,
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
                        var command = context.streamingXcodeBuild().option(.destination(destination)).option(.testProductsPath(products))
                            .option(.resultBundlePath(resultPath)).testWithoutBuilding()
                        if let plan { command = command.option(.testPlan(plan)) }
                        let serial = options.serial == true || serialDestinations.contains(destination)
                        if serial { command = command.option(.parallelTestingEnabled("NO")) }
                        for test in selectors ?? options.onlyTesting ?? [] { command = command.option(.onlyTesting(test)) }
                        for test in options.skipTesting ?? [] { command = command.option(.skipTesting(test)) }
                        for config in configurations { command = command.option(.onlyTestConfiguration(config)) }
                        if options.retryOnFailure == true { command = command.option(.retryTestsOnFailure) }
                        try await action.resetIOSAppInstallationIfNeeded(scheme: scheme, destination: destination, context: context)
                        let output = try await capture(command, directory: directory)
                        let log = output.stdout + output.stderr
                        let run = try await readResults(resultPath)
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
                                metadata: metadata, destinationID: placed.id)
                        }
                        let failures = scopedCases.filter { $0.status == .failed || $0.status == .errored }
                        attempts.append(
                            .init(
                                attemptNumber: number, reason: reason,
                                metadata: [
                                    "plan": plan ?? "default", "destination": destination, "serial": String(serial),
                                    "exit_code": String(output.exitCode),
                                ],
                                summary: run.summary, failedTests: failures, source: resultPath))
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
                attempts: attempts, initialFailedTests: initialFailures,
                flakyTests: flaky, persistentFailedTests: outstanding,
                summary: .init(
                    passed: initialCases.filter { $0.status == .passed }.count + flaky.count,
                    failed: outstanding.filter { $0.status == .failed }.count,
                    skipped: initialCases.filter { $0.status == .skipped }.count, flaky: flaky.count,
                    errored: max(1, errored) + outstanding.filter { $0.status == .errored }.count),
                testCases: finalTestCases(initialCases, remaining: outstanding, flaky: flaky))
            try? writeJSON(report, to: root.appendingPathComponent("report.json"))
            if let path = options.reportPath { try? writeJSON(report, to: URL(fileURLWithPath: path)) }
            throw error
        }
        await teardown(owned)
        leases.forEach { $0.release() }
        let report = TestRunReport(
            runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: root.path, destinations: reportDestinations,
            attempts: attempts, initialFailedTests: initialFailures, flakyTests: flaky, persistentFailedTests: remainingAll,
            summary: .init(
                passed: passed + flaky.count, failed: remainingAll.filter { $0.status == .failed }.count,
                skipped: skipped, flaky: flaky.count, errored: errored + remainingAll.filter { $0.status == .errored }.count),
            testCases: finalTestCases(initialCases, remaining: remainingAll, flaky: flaky))
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
    private func readResults(_ path: String) async throws -> ParsedTestRun {
        var errorMessage = "Structured test results unavailable"
        for number in 1...3 {
            do { return try await IOSXCResultTestParser(shell: context.shell).parse(xcresultPath: path) } catch {
                if Task.isCancelled || error is CancellationError { throw error }
                errorMessage = String(describing: error)
                if number < 3 { try await Task.sleep(for: .milliseconds(250 * number)) }
            }
        }
        return ParsedTestRun(
            runner: .xcodebuild, buildSystem: context.config.iosBuildSystem, source: path, summary: .init(errored: 1),
            diagnostics: [.init(severity: .error, message: errorMessage)])
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

    private func capture(_ command: XcodeBuild, directory: URL) async throws -> ShellOutput {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output: ShellOutput
        do { output = try await command.run() } catch let ShellError.exitFailure(_, captured) { output = captured } catch {
            try? saveInterruptedTestOutput(error, directory: directory)
            throw error
        }
        saveEvidence("attempt logs", logger: context.logger) {
            try output.stdout.write(to: directory.appendingPathComponent("stdout.log"), atomically: true, encoding: .utf8)
            try output.stderr.write(to: directory.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)
            try writeJSON(
                ["arguments": command.command().arguments, "exit_code": [String(output.exitCode)]],
                to: directory.appendingPathComponent("command.json"))
        }
        return output
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

import Foundation
import MobileCore
import SwiftyShell
import Synchronization
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Native test products: build once, test elsewhere")
struct NativeTestProductsTests {
    @Test("Product reuse options are rejected where they cannot work")
    func validation() throws {
        func validate(_ options: TestAction.Options, platform: Platform = .ios, system: AppFramework = .native) throws {
            try TestAction.validateProductReuse(options: options, platform: platform, buildSystem: system)
        }
        try validate(.init())
        try validate(.init(buildForTestingOnly: true))
        try validate(.init(useTestProducts: "build/tests.xctestproducts"))
        #expect(throws: ShipItError.self) { try validate(.init(buildForTestingOnly: true, useTestProducts: "x")) }
        #expect(throws: ShipItError.self) { try validate(.init(legacyCombinedTest: true, buildForTestingOnly: true)) }
        #expect(throws: ShipItError.self) { try validate(.init(testProductsPath: "a", useTestProducts: "b")) }
        #expect(throws: ShipItError.self) { try validate(.init(buildForTestingOnly: true), platform: .android) }
        #expect(throws: ShipItError.self) { try validate(.init(useTestProducts: "x"), system: .flutter) }
    }

    #if os(macOS)
    @Test("Build-only runs build-for-testing once, runs no tests, and reports where the products are")
    func buildOnly() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let products = scratch.url.appendingPathComponent("tests.xctestproducts").path
        let commands = Mutex([[String]]())
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            commands.withLock { $0.append(args) }
            if args.contains("build-for-testing"), let index = args.firstIndex(of: "-testProductsPath") {
                try? FileManager.default.createDirectory(atPath: args[index + 1], withIntermediateDirectories: true)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let result = try await TestAction().run(
            with: .init(
                scheme: "App", destination: "platform=iOS Simulator,id=mock", testProductsPath: products, buildForTestingOnly: true),
            context: .mock(executor: executor))
        let recorded = commands.withLock { $0 }
        #expect(recorded.filter { $0.contains("build-for-testing") }.count == 1)
        #expect(recorded.allSatisfy { !$0.contains("test-without-building") })
        #expect(result.testProductsPath == products)
        #expect(result.report == nil)
        #expect(FileManager.default.fileExists(atPath: products))
    }

    @Test("A failed build-only run still fails the build and writes the failure report")
    func buildOnlyFailure() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let reportPath = scratch.url.appendingPathComponent("report.json")
        let executor = MockExecutor { _, _ in .init(stdout: "", stderr: "error: build input file cannot be found", exitCode: 65) }
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(
                with: .init(
                    scheme: "App", destination: "platform=iOS Simulator,id=mock",
                    testProductsPath: scratch.url.appendingPathComponent("p.xctestproducts").path, buildForTestingOnly: true,
                    reportPath: reportPath.path), context: .mock(executor: executor))
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: reportPath))
        #expect(report.summary.errored == 1)
        #expect(report.attempts.first?.reason == "build")
    }

    @Test("Reusing products skips the build, runs test-without-building from them, and has no build time")
    func reuseProducts() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let products = scratch.url.appendingPathComponent("tests.xctestproducts")
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let commands = Mutex([[String]]())
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            commands.withLock { $0.append(args) }
            if args.contains("test-without-building") {
                writeResultBundle(for: args)
                return .init(stdout: "Test passed", stderr: "", exitCode: 0)
            }
            if args.contains("summary") { return .init(stdout: "{\"metrics\":{\"testsCount\":1}}", stderr: "", exitCode: 0) }
            if args.contains("tests") {
                return .init(
                    stdout: "{\"testNodes\":[{\"nodeType\":\"Test Case\",\"nodeIdentifier\":\"AppTests/C/test()\",\"result\":\"Passed\"}]}",
                    stderr: "", exitCode: 0)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let result = try await TestAction().run(
            with: .init(scheme: "App", destination: "platform=iOS Simulator,id=mock", useTestProducts: products.path),
            context: .mock(executor: executor))
        let recorded = commands.withLock { $0 }
        #expect(recorded.allSatisfy { !$0.contains("build-for-testing") })
        let test = try #require(recorded.first { $0.contains("test-without-building") })
        #expect(test.contains(products.path))
        #expect(result.passCount == 1)
        #expect(result.report?.buildSeconds == nil)
        #expect(result.testProductsPath == products.path)
    }

    @Test("Reusing products that are not there fails with a configuration error")
    func reuseMissingProducts() async throws {
        let executor = MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }
        await #expect {
            _ = try await TestAction().run(
                with: .init(scheme: "App", destination: "platform=iOS Simulator,id=mock", useTestProducts: "/no/such.xctestproducts"),
                context: .mock(executor: executor))
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("use_test_products")
        }
    }

    // MARK: Simulator hygiene between retries

    /// A native run whose first attempt fails one test and whose rerun passes it, on a simulator whose health the
    /// caller scripts. Returns the commands in the order they ran.
    private func rerunCommands(
        simulatorResponsive: Bool, firstAttemptExit: Int32 = 65, infrastructureLog: String = ""
    ) async throws
        -> [[String]]
    {
        let commands = Mutex([[String]]())
        let attempt = Mutex(0)
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            commands.withLock { $0.append(args) }
            if args.contains("list") {
                return .init(stdout: "{\"devices\":{\"rt\":[{\"udid\":\"SIM-1\",\"state\":\"Booted\"}]}}", stderr: "", exitCode: 0)
            }
            if args.contains("getenv") {
                return .init(stdout: simulatorResponsive ? "/Users/sim\n" : "", stderr: "", exitCode: simulatorResponsive ? 0 : 1)
            }
            if args.contains("test-without-building") {
                writeResultBundle(for: args)
                let number = attempt.withLock {
                    $0 += 1
                    return $0
                }
                return number == 1
                    ? .init(stdout: "", stderr: infrastructureLog, exitCode: firstAttemptExit)
                    : .init(stdout: "ok", stderr: "", exitCode: 0)
            }
            if args.contains("summary") { return .init(stdout: "{}", stderr: "", exitCode: 0) }
            if args.contains("tests") {
                let result = attempt.withLock { $0 } == 1 ? "Failed" : "Passed"
                return .init(
                    stdout:
                        "{\"testNodes\":[{\"nodeType\":\"Test Case\",\"nodeIdentifier\":\"AppTests/C/flaky()\",\"result\":\"\(result)\"}]}",
                    stderr: "", exitCode: 0)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        // Claims go to a scratch directory, never the developer's real ~/.amoo/leases.
        let claims = try TemporaryDirectory()
        defer { try? claims.remove() }
        let context = makeTestActionContext(
            shell: ShellContext(executor: executor, environment: ["AMOO_LEASE_DIR": claims.url.path]),
            config: ResolvedConfig(platform: .ios),
            platform: .ios)
        _ = try await TestAction().run(
            with: .init(
                scheme: "App", destination: "platform=iOS Simulator,id=SIM-1", rerunFailedTests: .init(enabled: true, maxAttempts: 2)),
            context: context)
        return commands.withLock { $0 }
    }

    @Test("A hung simulator is restarted before the failed tests are rerun")
    func recoversHungSimulatorBeforeRerun() async throws {
        let recorded = try await rerunCommands(simulatorResponsive: false)
        let tests = recorded.indices.filter { recorded[$0].contains("test-without-building") }
        #expect(tests.count == 2)
        let shutdown = try #require(recorded.indices.first { recorded[$0].contains("shutdown") && recorded[$0].contains("SIM-1") })
        let boot = try #require(recorded.indices.last { recorded[$0].contains("boot") && recorded[$0].contains("SIM-1") })
        #expect(tests[0] < shutdown && shutdown < tests[1], "recovery must happen between the attempts: \(recorded)")
        #expect(shutdown < boot && boot < tests[1])
        #expect(recorded.allSatisfy { !$0.contains("erase") }, "recovery must never erase a simulator")
    }

    @Test("A healthy simulator is left alone between a failed test and its rerun")
    func leavesHealthySimulatorAlone() async throws {
        let recorded = try await rerunCommands(simulatorResponsive: true)
        #expect(recorded.filter { $0.contains("test-without-building") }.count == 2)
        #expect(recorded.allSatisfy { !$0.contains("shutdown") })
    }
    #endif
}

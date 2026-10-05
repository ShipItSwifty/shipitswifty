import ShipItKit

let reporter = JSONReporter()
let report = TestRunReport(
    runner: .xcodebuild,
    buildSystem: .native,
    source: "./build/MyApp-tests.xcresult",
    destinations: [TestDestination(platform: .ios, kind: .simulator, name: "iPhone 16")],
    summary: TestSummary(passed: 42, failed: 1)
)

print(try reporter.encodeAny(report))

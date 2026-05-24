import ShipItKit

let reporter = JSONReporter()
let report = TestRunReport(
    platform: "ios",
    runner: "xcodebuild",
    source: "./build/MyApp-tests.xcresult",
    summary: TestSummary(passed: 42, failed: 1)
)

print(try reporter.encodeAny(report))

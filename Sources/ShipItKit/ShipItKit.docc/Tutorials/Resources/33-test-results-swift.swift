import ShipItKit

let context = try await buildFallbackActionContext(platform: .ios)
let result = try await TestResultsAction().run(
    with: .init(xcresultPath: "./build/MyApp-tests.xcresult"),
    context: context
)

print(result.report.summary.failed)

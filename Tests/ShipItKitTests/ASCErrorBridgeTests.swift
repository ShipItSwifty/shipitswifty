import AppStoreConnectKit
import Foundation
import Testing

@testable import ShipItKit

struct ASCErrorBridgeTests {
    @Test func decodingFailurePreservesDiagnosticsAndAPIExitCode() {
        let underlying = NSError(
            domain: "ASCErrorBridgeTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing required data field"]
        )
        let error = ShipItError(
            asc: .decodingFailed(path: "/v1/apps", type: "ASCListResponse<App>", underlying: underlying)
        )

        guard case .apiDecodingFailed(let path, let type, let cause) = error else {
            Issue.record("Expected an API decoding failure, got \(error)")
            return
        }
        #expect(path == "/v1/apps")
        #expect(type == "ASCListResponse<App>")
        #expect(cause.localizedDescription == "Missing required data field")
        #expect(error.exitCode == 30)
        #expect(error.localizedDescription.contains(path))
        #expect(error.localizedDescription.contains(type))
        #expect(error.localizedDescription.contains(cause.localizedDescription))
    }
}

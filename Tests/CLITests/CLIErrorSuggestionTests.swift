import Foundation
import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("CLI Error Suggestions")
struct CLIErrorSuggestionTests {

    @Test("Missing Shipfile suggests checking path and --shipfile")
    func missingShipfileSuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "Shipfile not found at /tmp/MissingShipfile.yml")
        )

        #expect(suggestions.contains { $0.contains("filepath is correct") })
        #expect(suggestions.contains { $0.contains("--shipfile") })
    }

    @Test("Missing scheme suggests CLI flag or Shipfile config")
    func missingSchemeSuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "Build requires a scheme.")
        )

        #expect(suggestions.contains { $0.contains("--scheme") })
        #expect(suggestions.contains { $0.contains("app.scheme") })
    }

    @Test("Missing bundle ID suggests config or env")
    func missingBundleIDSuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "Upload requires app.bundle_id")
        )

        #expect(suggestions.contains { $0.contains("app.bundle_id") })
        #expect(suggestions.contains { $0.contains("SHIPIT_APP__BUNDLE_ID") })
    }

    @Test("Missing upload file suggests checking path")
    func missingUploadFileSuggestions() {
        let suggestions = errorSuggestions(
            for: .uploadFailed(asset: "App.ipa", reason: "IPA not found: /tmp/App.ipa")
        )

        #expect(suggestions.contains { $0.contains("filepath exists") })
        #expect(suggestions.contains { $0.contains("absolute path") })
    }

    @Test("JWT generation failure suggests ASC credential checks")
    func jwtGenerationSuggestions() {
        let suggestions = errorSuggestions(
            for: .jwtGenerationFailed(underlying: NSError(domain: "Test", code: 1))
        )

        #expect(suggestions.contains { $0.contains("ASC_KEY_ID") })
        #expect(suggestions.contains { $0.contains("ASC_PRIVATE_KEY_PATH") })
    }
}

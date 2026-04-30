import Foundation
import Testing

@testable import CLI
@testable import ShipItKit

@Suite("CLI Error Suggestion Audit")
struct CLIErrorSuggestionAuditTests {

    @Test("Git push failure suggests remote and upstream checks")
    func gitPushFailureSuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "git push failed: fatal: The current branch has no upstream branch.")
        )

        #expect(suggestions.contains { $0.contains("remote exists") })
        #expect(suggestions.contains { $0.contains("no upstream") || $0.contains("upstream") })
    }

    @Test("dSYM upload URL failure suggests workflow config fix")
    func dsymUploadUrlSuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "dsym upload requires an upload URL")
        )

        #expect(suggestions.contains { $0.contains("upload_url") })
        #expect(suggestions.contains { $0.contains("HTTPS") || $0.contains("valid") })
    }

    @Test("Info plist key failure suggests checking target plist")
    func infoPlistKeySuggestions() {
        let suggestions = errorSuggestions(
            for: .invalidConfiguration(reason: "Key 'CFBundleVersion' not found in Info.plist")
        )

        #expect(suggestions.contains { $0.contains("Info.plist") })
        #expect(suggestions.contains { $0.contains("--scheme") || $0.contains("app.project") })
    }

    @Test("Webhook response failure suggests checking service config")
    func webhookFailureSuggestions() {
        let suggestions = errorSuggestions(
            for: .uploadFailed(asset: "slack", reason: "Slack webhook returned non-2xx response")
        )

        #expect(suggestions.contains { $0.contains("still active") || $0.contains("valid") })
        #expect(suggestions.contains { $0.contains("credentials") || $0.contains("configuration") })
    }

    @Test("Keychain certificate import failure suggests checking p12 path and password")
    func keychainImportSuggestions() {
        let suggestions = errorSuggestions(
            for: .keychainError(
                underlying: ShipItError.invalidConfiguration(
                    reason: "Certificate import failed: SecKeychainItemImport: Unknown format in import.")
            )
        )

        #expect(suggestions.contains { $0.contains(".p12") })
        #expect(suggestions.contains { $0.contains("password") || $0.contains("readable") })
    }
}

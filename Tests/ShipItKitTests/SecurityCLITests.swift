import Testing

@testable import ShipItKit

struct SecurityCLITests {
    @Test func buildsAvailabilityProbeWithSupportedHelpSubcommand() {
        let command = SecurityCLI()
            .help()
            .command()

        #expect(command.executableName == "security")
        #expect(command.arguments == ["help"])
    }

    @Test func buildsCreateKeychainCommand() {
        let command = SecurityCLI()
            .createKeychain(name: "ci.keychain", password: "secret")
            .command()

        #expect(command.arguments == ["create-keychain", "-p", "secret", "ci.keychain"])
    }

    @Test func buildsCertificateImportWithTrustedApplications() {
        let command = SecurityCLI()
            .importCertificate(
                at: "/tmp/cert.p12",
                keychainName: "ci.keychain",
                password: "p12pass",
                trustedApplications: ["/usr/bin/codesign", "/usr/bin/security"]
            )
            .command()

        #expect(
            command.arguments == [
                "import", "/tmp/cert.p12",
                "-k", "ci.keychain",
                "-P", "p12pass",
                "-T", "/usr/bin/codesign",
                "-T", "/usr/bin/security",
            ])
    }
}

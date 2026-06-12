#if os(macOS)
import Foundation
import Testing

@testable import ShipItKit

@Suite("CertVaultCrypto")
struct CertVaultCryptoTests {

    private let plaintext = Data("p12-certificate-bytes".utf8)
    private let password = "correct horse battery staple"

    @Test("seal then open round-trips the plaintext")
    func sealOpenRoundTrip() throws {
        let sealed = try CertVaultCrypto.seal(plaintext, password: password)
        let opened = try CertVaultCrypto.open(sealed, password: password)
        #expect(opened == plaintext)
    }

    @Test("sealed file starts with the format version byte")
    func sealedFileHasVersionPrefix() throws {
        let sealed = try CertVaultCrypto.seal(plaintext, password: password)
        #expect(sealed.first == CertVaultCrypto.formatVersion)
    }

    @Test("sealing twice produces different salts and ciphertexts")
    func sealUsesRandomPerFileSalt() throws {
        let first = try CertVaultCrypto.seal(plaintext, password: password)
        let second = try CertVaultCrypto.seal(plaintext, password: password)

        let firstSalt = first[1..<(1 + CertVaultCrypto.saltByteCount)]
        let secondSalt = second[1..<(1 + CertVaultCrypto.saltByteCount)]
        #expect(firstSalt != secondSalt)
        #expect(first != second)
    }

    @Test("open with the wrong password throws")
    func openWrongPasswordThrows() throws {
        let sealed = try CertVaultCrypto.seal(plaintext, password: password)
        #expect(throws: (any Error).self) {
            try CertVaultCrypto.open(sealed, password: "wrong-password")
        }
    }

    @Test("open with tampered ciphertext throws")
    func openTamperedCiphertextThrows() throws {
        var sealed = try CertVaultCrypto.seal(plaintext, password: password)
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) {
            try CertVaultCrypto.open(sealed, password: password)
        }
    }

    @Test("open rejects truncated data")
    func openTruncatedDataThrows() {
        let tooShort = Data([CertVaultCrypto.formatVersion]) + Data(repeating: 0, count: 10)
        #expect(throws: CertVaultCrypto.FormatError.self) {
            try CertVaultCrypto.open(tooShort, password: password)
        }
    }

    @Test("open rejects an unsupported format version")
    func openUnsupportedVersionThrows() throws {
        var sealed = try CertVaultCrypto.seal(plaintext, password: password)
        sealed[0] = 0xFE
        #expect(throws: CertVaultCrypto.FormatError.self) {
            try CertVaultCrypto.open(sealed, password: password)
        }
    }

    @Test("open works on a data slice with a non-zero start index")
    func openHandlesDataSlices() throws {
        let sealed = try CertVaultCrypto.seal(plaintext, password: password)
        let padded = Data([0xAA, 0xBB]) + sealed
        let slice = padded[2...]
        let opened = try CertVaultCrypto.open(slice, password: password)
        #expect(opened == plaintext)
    }
}
#endif

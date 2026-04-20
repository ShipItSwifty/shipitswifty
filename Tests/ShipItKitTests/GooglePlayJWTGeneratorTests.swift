import Foundation
import Testing
@testable import ShipItKit

@Suite("GooglePlayJWTGenerator")
struct GooglePlayJWTGeneratorTests {
    @Test("buildJWT creates an RS256 service-account assertion from an RSA key")
    func buildJWTUsesRSAServiceAccountKey() async throws {
        let credentials = GoogleServiceAccountCredentials(
            clientEmail: "shipit-test@project.iam.gserviceaccount.com",
            privateKey: testRSAPrivateKeyPEM,
            tokenUri: "https://oauth2.googleapis.com/token",
            projectId: "shipit-test"
        )

        let generator = GooglePlayJWTGenerator(credentials: credentials)
        let token = try await generator.buildJWT()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)

        #expect(parts.count == 3)
        let header = try decodeBase64URLJSON(String(parts[0]))
        let payload = try decodeBase64URLJSON(String(parts[1]))
        let signature = try #require(base64URLDecode(String(parts[2])))

        #expect(header["alg"] as? String == "RS256")
        #expect(header["typ"] as? String == "JWT")
        #expect(payload["iss"] as? String == credentials.clientEmail)
        #expect(payload["aud"] as? String == credentials.tokenUri)
        #expect(payload["scope"] as? String == "https://www.googleapis.com/auth/androidpublisher")
        #expect(signature.isEmpty == false)
    }
}

private let testRSAPrivateKeyPEM = """
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDd19chv0wmMdfh
Bp3FSWdGpx2ap4f22iexPoj0azZxEljSOWCcwNvzm3byQuCcHlXo3Jgkm+nu2+0s
+qIfQylBkOw1U4YXUlccLfuL6P8454QsOiCkEuLQ0bueLxVpiZI5PJNcpbPZKu5F
uogs3D9FHTqAPQE+7ufzRNYwZsyn4m19kEavft/vm6/Zyk6n4QN+d7l9OcCKm5a7
avcb98lj7IL/cUEFlSZgb6AMEolYL3aIsM649ltWIYdKhMZbx+19Ek5rbizX+dJr
dcYCprFcf+D6t1+hTUHruEetyieNnScfI1bhEKomsnvt5TJqm3n/ahlJbLFEzasS
q+/S+KuvAgMBAAECggEAMNO3WYmpwIRa7//NTOV1kjLpDKeQAPCOKPBLI4TPdD6m
Bwsy7P1zy9/tY6/9kM8KeJjI8dHRQM3uG2bEtR3KoFA99RS/oDVyz9R9F5O+TO+E
A1n94i739h8bbNsPGu35HZjsFEmyVnug+v7txvXpBRTEUgJbWlcp/Tyq6fdOVyrR
axQOm7BdBn7c/FkObbbH4BncWWYmcF6LFgJxK8A+VdGXvLZqGV0Cv4ihEPOsfki4
AuMFArkAQajebKW8tKj4aJuE7SelM6zDYT+KWLnsL8RynS0DUJ4INKMOCP5euvgd
ddaI2orxrvoTxDgXZdA8BFhodXNKgM1CzZd8fX6dQQKBgQD+6E6C0ICSkSQW5F7n
4g4UUUrOV0rZfhAaSJn7m9Ieep/5BmrcsHejFmxMaroyPwkx4AC2imDT4QzUPiUB
XQNQyOweD8EEZ847PKQ6ctwYmpANkhhuzo8aBm0/dmNQgdG62+1oGbUEKR7gXeni
cbTtbxpF+txjdlJhxue+RlEAbwKBgQDey0EdMLZt+UyPWDg2Z+HeBojnt+FmRa77
aeye/ysI5H2cKuAPfDhapXftMJTg0fpYuIAbWHogkl76/OU1Eq/B60P8inv/7HLG
b4TNjSRo7u71UnXz7T4eekL9SHV1xkDi80jW4VgTvjRH9Qn4RjcwL6akJSwBGZEh
uLIm1IoowQKBgQD42/d6QvCjJsvjBYWaQNmaAFtV42cRur8hyet69v9F/lWbmyZM
2oOSVtvYJwIs99mUNaq8i5BIipgpxZn/IL2R6vaJyruX/3gZ4PQ8k9JIuu0UMqNj
2ole0RNrN7tx56vID9pRHXfZ3gNk7IrgJj6K50LxOx5ahDOdfcDVxHRkRQKBgQC7
OLCqOAJF3kaQ+wCZ76gl7PXlS2e1iv9ltPisEB/45BIORxVszeWJfx2Ni9LALpQj
NEArOqm+b2IzpotykxZxbiP+t91GDkvRJ2vBVEdxir/yFe6bIhWehP2AXQCgDQ7/
6JOgR1O9m4vRoEBVi6Pa8WAm9jnJXtPQM6Y57UeAwQKBgQDaMv0myNAYTRLinlUw
1ZlUwl6NqBWygBa9HAVw8sXQLa9Ls1866CsM5TUhRoMCVB1wb5/jikt0QNkoAyV1
5/s4XxZ+0jubQV5Mb0D8Kqv2uf1C4psaSyxClq4s3WjSi1P833aKevIAq1Gk0z5x
CLXs+qygZfFfEzGbH4FsyNhcQQ==
-----END PRIVATE KEY-----
"""

private func decodeBase64URLJSON(_ base64url: String) throws -> [String: Any] {
    guard let data = base64URLDecode(base64url),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw GooglePlayJWTTestError.invalidJWTPart
    }
    return json
}

private func base64URLDecode(_ base64url: String) -> Data? {
    var base64 = base64url
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
}

private enum GooglePlayJWTTestError: Error {
    case invalidJWTPart
}

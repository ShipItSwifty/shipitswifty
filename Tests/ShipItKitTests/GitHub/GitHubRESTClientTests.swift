import Foundation
import TestCommons
import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("GitHub REST client")
struct GitHubRESTClientTests {
    private func client(_ stub: StubbedURLSession) throws -> GitHubRESTClient {
        try GitHubRESTClient(repository: "octo/app", token: "ghs_secret", session: stub.session)
    }

    @Test("Listing sends the token and API version, filters pull requests, and asks for all states")
    func listsIssues() async throws {
        let stub = try StubbedURLSession(
            responses: [
                .json(
                    """
                    [{"number":1,"title":"Test failing: A","body":"b","state":"open"},
                     {"number":2,"title":"A pull request","body":null,"state":"open","pull_request":{}},
                     {"number":3,"title":"Closed","body":null,"state":"closed"}]
                    """)
            ])
        defer { stub.invalidate() }
        let issues = try await client(stub).issues(withLabel: "shipit-test-failure")
        #expect(issues.map(\.number) == [1, 3])
        #expect(issues[1].body == "")
        #expect(issues[1].state == .closed)
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghs_secret")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("/repos/octo/app/issues"))
        #expect(url.contains("labels=shipit-test-failure"))
        #expect(url.contains("state=all"))
    }

    @Test("Listing follows pages until one comes back short")
    func paginates() async throws {
        let full =
            "[" + (1...100).map { "{\"number\":\($0),\"title\":\"t\",\"body\":\"\",\"state\":\"open\"}" }.joined(separator: ",") + "]"
        let stub = try StubbedURLSession(responses: [.json(full), .json("[{\"number\":101,\"title\":\"t\",\"state\":\"open\"}]")])
        defer { stub.invalidate() }
        #expect(try await client(stub).issues(withLabel: "x").count == 101)
        #expect(stub.requests.count == 2)
        #expect(stub.requests.last?.url?.absoluteString.contains("page=2") == true)
    }

    @Test("Creating, updating and commenting send the right method, path and body")
    func writes() async throws {
        let stub = try StubbedURLSession(
            responses: [
                .json("{\"number\":7,\"title\":\"T\",\"body\":\"B\",\"state\":\"open\"}", statusCode: 201), .json("{}"),
                .json("{}", statusCode: 201),
            ])
        defer { stub.invalidate() }
        let api = try client(stub)
        let issue = try await api.createIssue(title: "T", body: "B", labels: ["shipit-test-failure"])
        try await api.updateIssue(number: issue.number, body: nil, state: .closed)
        try await api.addComment(number: 7, body: "hello")

        let requests = stub.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "POST"])
        #expect(
            requests.map { $0.url?.path } == ["/repos/octo/app/issues", "/repos/octo/app/issues/7", "/repos/octo/app/issues/7/comments"])
        let created = try #require(JSONSerialization.jsonObject(with: requests[0].bodyData()) as? [String: Any])
        #expect(created["labels"] as? [String] == ["shipit-test-failure"])
        let patched = try #require(JSONSerialization.jsonObject(with: requests[1].bodyData()) as? [String: Any])
        #expect(patched["state"] as? String == "closed")
        #expect(patched["body"] == nil, "an unset body must be left alone, not blanked")
    }

    @Test("An HTTP error becomes an API error carrying the status")
    func httpError() async throws {
        let stub = try StubbedURLSession(responses: [.text("{\"message\":\"Resource not accessible by integration\"}", statusCode: 403)])
        defer { stub.invalidate() }
        await #expect {
            _ = try await client(stub).issues(withLabel: "x")
        } throws: { error in
            guard case ShipItError.apiError(let status, let body) = error else { return false }
            return status == 403 && body.contains("not accessible")
        }
    }

    @Test("A malformed repository or empty token is rejected before any request")
    func rejectsBadInput() throws {
        #expect(throws: ShipItError.self) { try GitHubRESTClient(repository: "no-slash", token: "t") }
        #expect(throws: ShipItError.self) { try GitHubRESTClient(repository: "a/b/c", token: "t") }
        #expect(throws: ShipItError.self) { try GitHubRESTClient(repository: "a/b", token: "") }
    }
}

extension URLRequest {
    /// The body of a request a stubbed session received, which URLSession may hand over as a stream.
    fileprivate func bodyData() throws -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

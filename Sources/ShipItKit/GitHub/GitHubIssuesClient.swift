import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An issue as ShipIt needs to see it. Pull requests share GitHub's issues endpoint and are never returned.
public struct GitHubIssue: Sendable, Equatable {
    public enum State: String, Codable, Sendable { case open, closed }

    public let number: Int
    public let title: String
    public let body: String
    public let state: State

    public init(number: Int, title: String, body: String, state: State) {
        self.number = number
        self.title = title
        self.body = body
        self.state = state
    }
}

/// The few issue operations test reporting needs. A protocol so the policy in ``GitHubIssueSync`` runs against a
/// fake in tests and against nothing at all in a dry run.
public protocol GitHubIssuesAPI: Sendable {
    /// Every issue carrying `label`, open and closed.
    func issues(withLabel label: String) async throws -> [GitHubIssue]
    func createIssue(title: String, body: String, labels: [String]) async throws -> GitHubIssue
    func updateIssue(number: Int, body: String?, state: GitHubIssue.State?) async throws
    func addComment(number: Int, body: String) async throws
}

/// GitHub's REST API over `URLSession`.
///
/// Needs a token with `issues: write`. The token is sent only to `apiBase` and is never logged.
public struct GitHubRESTClient: GitHubIssuesAPI {
    public let repository: String
    private let token: String
    private let apiBase: URL
    private let session: URLSession
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GitHubRESTClient.self)

    /// 10 pages of 100 covers far more test-failure issues than a repository should have open at once.
    private static let pageLimit = 10

    public init(
        repository: String, token: String, apiBase: URL = URL(string: "https://api.github.com")!,
        session: URLSession = .shared
    ) throws {
        guard repository.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            throw ShipItError.invalidConfiguration(reason: "Repository must look like owner/name, got '\(repository)'")
        }
        guard !token.isEmpty else { throw ShipItError.invalidConfiguration(reason: "A GitHub token is required to file issues") }
        self.repository = repository
        self.token = token
        self.apiBase = apiBase
        self.session = session
    }

    public func issues(withLabel label: String) async throws -> [GitHubIssue] {
        var found: [GitHubIssue] = []
        for page in 1...Self.pageLimit {
            var components = URLComponents()
            components.queryItems = [
                .init(name: "labels", value: label), .init(name: "state", value: "all"), .init(name: "per_page", value: "100"),
                .init(name: "page", value: String(page)),
            ]
            let data = try await send("GET", "/repos/\(repository)/issues?\(components.percentEncodedQuery ?? "")")
            let batch = try JSONDecoder().decode([RawIssue].self, from: data)
            found += batch.filter { $0.pullRequest == nil }.map(\.issue)
            if batch.count < 100 { break }
        }
        return found
    }

    public func createIssue(title: String, body: String, labels: [String]) async throws -> GitHubIssue {
        let data = try await send("POST", "/repos/\(repository)/issues", ["title": title, "body": body, "labels": labels])
        return try JSONDecoder().decode(RawIssue.self, from: data).issue
    }

    public func updateIssue(number: Int, body: String?, state: GitHubIssue.State?) async throws {
        var fields: [String: Any] = [:]
        if let body { fields["body"] = body }
        if let state { fields["state"] = state.rawValue }
        _ = try await send("PATCH", "/repos/\(repository)/issues/\(number)", fields)
    }

    public func addComment(number: Int, body: String) async throws {
        _ = try await send("POST", "/repos/\(repository)/issues/\(number)/comments", ["body": body])
    }

    private struct RawIssue: Decodable {
        struct PullRequestMarker: Decodable {}
        let number: Int
        let title: String
        let body: String?
        let state: GitHubIssue.State
        /// Present only on pull requests, which the issues endpoint also returns.
        let pullRequest: PullRequestMarker?
        var issue: GitHubIssue { GitHubIssue(number: number, title: title, body: body ?? "", state: state) }

        private enum CodingKeys: String, CodingKey {
            case number, title, body, state
            case pullRequest = "pull_request"
        }
    }

    private func send(_ method: String, _ path: String, _ json: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: apiBase) else {
            throw ShipItError.invalidConfiguration(reason: "Invalid GitHub API path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        logger.debug("GitHub request", metadata: ["method": "\(method)", "path": "\(path)"])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.debug("GitHub response", metadata: ["method": "\(method)", "path": "\(path)", "status": "\(status)"])
        guard (200..<300).contains(status) else {
            logger.error("GitHub request failed", metadata: ["method": "\(method)", "path": "\(path)", "status": "\(status)"])
            throw ShipItError.apiError(statusCode: status, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }
}

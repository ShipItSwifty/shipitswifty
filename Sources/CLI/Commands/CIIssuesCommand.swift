import ArgumentParser
import Foundation
import ShipItKit

/// What `shipit ci issues` did, or would do under `--dry-run`.
struct CIIssuesResult: Codable, Sendable {
    /// Why nothing was done, when the run was out of scope.
    let skipped: String?
    let actions: [IssueSyncAction]
}

/// Keep GitHub issues in step with test reports: one per consistently failing test, one rolling issue for flaky tests.
///
/// Needs `GITHUB_TOKEN` in the environment with `issues: write`; the token is never accepted as an argument.
///
/// ## Usage
/// ```
/// GITHUB_TOKEN=... shipit ci issues --report build/report.json --repository owner/name --only-ref main
/// shipit ci issues --report build/report.json --dry-run     # plan only; no token needed
/// ```
struct CIIssuesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "issues",
        abstract: "File, update, reopen and close GitHub issues for failing and flaky tests"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .customLong("report"), help: "TestRunReport JSON from `shipit test --report-path` (repeatable; shards are merged)")
    var reports: [String] = []
    @Option(name: .long, help: "owner/name (default: $GITHUB_REPOSITORY)")
    var repository: String?
    @Option(name: .customLong("label"), help: "Extra label for every issue ShipIt files (repeatable)")
    var labels: [String] = []
    @Option(name: .long, help: "Close an issue after this many consecutive clean runs; 0 never closes (default: 3)")
    var closeAfterCleanRuns: Int = 3
    @Option(
        name: .long,
        help: "Only act when the current branch ($GITHUB_REF_NAME) is this one, so pull requests and feature branches never file issues")
    var onlyRef: String?
    @Option(name: .long, help: "Link to the run (default: built from GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID)")
    var runUrl: String?
    @Option(name: .long, help: "Link to the run's uploaded evidence")
    var artifactUrl: String?

    func run() async throws {
        do {
            let environment = ProcessInfo.processInfo.environment
            let digest = try TestRunDigest.load(reportPaths: reports)
            let branch = environment["GITHUB_REF_NAME"]
            if let onlyRef, branch != onlyRef {
                let reason = "Skipping issues: running on '\(branch ?? "unknown")', issues are only filed from '\(onlyRef)'."
                outputResult(
                    action: "ci-issues", result: CIIssuesResult(skipped: reason, actions: []), format: global.output,
                    colorMode: global.effectiveColorMode)
                return
            }
            let slug = repository ?? environment["GITHUB_REPOSITORY"]
            let api: any GitHubIssuesAPI
            if let token = environment["GITHUB_TOKEN"], !token.isEmpty, let slug {
                api = try GitHubRESTClient(repository: slug, token: token)
            } else if global.dryRun {
                // A plan with no GitHub access treats every test as new.
                api = OfflineGitHubIssues()
            } else {
                throw ShipItError.invalidConfiguration(
                    reason: "Filing issues needs GITHUB_TOKEN (issues: write) and --repository or GITHUB_REPOSITORY")
            }
            let defaultRunURL: String? = {
                guard let server = environment["GITHUB_SERVER_URL"], let slug, let id = environment["GITHUB_RUN_ID"] else { return nil }
                return "\(server)/\(slug)/actions/runs/\(id)"
            }()
            let sync = GitHubIssueSync(
                api: api,
                configuration: IssueSyncConfiguration(
                    extraLabels: labels, closeAfterCleanRuns: max(0, closeAfterCleanRuns), runID: environment["GITHUB_RUN_ID"],
                    runURL: runUrl ?? defaultRunURL, artifactURL: artifactUrl, branch: branch),
                dryRun: global.dryRun)
            let actions = try await sync.sync(digest)
            outputResult(
                action: "ci-issues", result: CIIssuesResult(skipped: nil, actions: actions), format: global.output,
                colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(action: "ci-issues", error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

/// Stands in for GitHub when a dry run has no token: nothing exists yet, and nothing is written.
private struct OfflineGitHubIssues: GitHubIssuesAPI {
    func issues(withLabel label: String) async throws -> [GitHubIssue] { [] }
    func createIssue(title: String, body: String, labels: [String]) async throws -> GitHubIssue {
        GitHubIssue(number: 0, title: title, body: body, state: .open)
    }
    func updateIssue(number: Int, body: String?, state: GitHubIssue.State?) async throws {}
    func addComment(number: Int, body: String) async throws {}
}

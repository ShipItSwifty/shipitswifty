import Foundation
import Logging
import SwiftyShell

/// Performs Git operations via SwiftyShell.
///
/// Supports status checks, committing version bumps, tagging releases,
/// and pushing to remote.
///
/// ## Usage
/// ```swift
/// let result = try await GitAction().run(
///     with: .init(operation: .ensureClean),
///     context: context
/// )
/// ```
public struct GitAction: Action {
    public static let name = "git"
    public static let description = "Git operations — status checks, tagging, committing"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", GitAction.self)

    /// Creates a `GitAction`.
    public init() {}

    /// Git operations.
    public enum GitOperation: String, Codable, Sendable {
        /// Fail if the working tree is not clean.
        case ensureClean
        /// Create an annotated git tag.
        case tag
        /// Commit all staged changes.
        case commit
        /// Push commits and tags to remote.
        case push
        /// Get the latest git log.
        case log
        /// Get the current commit hash.
        case hash
    }

    /// Configuration for the git action.
    public struct Options: Codable, Sendable {
        /// Operation to perform.
        public var operation: GitOperation

        /// Tag name (for `tag` operation).
        public var tagName: String?

        /// Tag message (for annotated tags).
        public var tagMessage: String?

        /// Commit message (for `commit` operation).
        public var commitMessage: String?

        /// Remote name (for `push` operation, default: `origin`).
        public var remote: String?

        /// Whether to push tags when pushing.
        public var pushTags: Bool?

        /// Creates `Options` for the git action.
        ///
        /// - Parameter operation: The git operation to perform.
        /// - Parameter tagName: Tag name (for `tag` operation).
        /// - Parameter tagMessage: Message for an annotated tag.
        /// - Parameter commitMessage: Commit message (for `commit` operation).
        /// - Parameter remote: Remote name for `push` (default: `origin`).
        /// - Parameter pushTags: Whether to push tags when pushing.
        public init(
            operation: GitOperation = .ensureClean,
            tagName: String? = nil,
            tagMessage: String? = nil,
            commitMessage: String? = nil,
            remote: String? = nil,
            pushTags: Bool? = nil
        ) {
            self.operation = operation
            self.tagName = tagName
            self.tagMessage = tagMessage
            self.commitMessage = commitMessage
            self.remote = remote
            self.pushTags = pushTags
        }
    }

    /// Result of a git operation.
    public struct Result: Codable, Sendable {
        /// Output from the git command.
        public let output: String

        /// Whether the working tree is clean (for `ensureClean`).
        public let isClean: Bool?

        /// Creates a `Result`.
        public init(output: String, isClean: Bool? = nil) {
            self.output = output
            self.isClean = isClean
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        logger.info("Git operation: \(options.operation.rawValue)")

        switch options.operation {
        case .ensureClean:
            return try await ensureClean(context: context)
        case .tag:
            return try await createTag(options: options, context: context)
        case .commit:
            return try await createCommit(options: options, context: context)
        case .push:
            return try await push(options: options, context: context)
        case .log:
            return try await getLog(context: context)
        case .hash:
            return try await getHash(context: context)
        }
    }

    // MARK: - Operations

    private func ensureClean(context: ActionContext) async throws -> Result {
        // `git status --porcelain` exits 0 on both clean and dirty trees;
        // stdout is empty only when the tree is clean.
        let output = try await GitCLI(context: context.shell).statusPorcelain().run()
        let isClean = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !isClean {
            throw ShipItError.invalidConfiguration(
                reason: "Working tree is not clean. Commit or stash changes before proceeding.\n\(output.stdout)"
            )
        }

        logger.info("Git working tree is clean")
        return Result(output: output.stdout, isClean: true)
    }

    private func createTag(options: Options, context: ActionContext) async throws -> Result {
        guard let tagName = options.tagName else {
            throw ShipItError.invalidConfiguration(reason: "git tag requires a tag name. Set tag_name in the workflow step options.")
        }

        let message = options.tagMessage ?? tagName
        logger.info("Creating git tag: \(tagName)")

        // Command.run() throws ShellError.exitFailure on non-zero exit.
        let output = try await GitCLI(context: context.shell)
            .annotatedTag(name: tagName, message: message)
            .run()
        return Result(output: output.stdout)
    }

    private func createCommit(options: Options, context: ActionContext) async throws -> Result {
        guard let message = options.commitMessage else {
            throw ShipItError.invalidConfiguration(
                reason: "git commit requires a commit message. Set commit_message in the workflow step options.")
        }

        logger.info("Creating git commit: \(message)")

        let git = GitCLI(context: context.shell)
        _ = try await git.addAll().run()
        let commitOutput = try await git.commit(message: message).run()
        return Result(output: commitOutput.stdout)
    }

    private func push(options: Options, context: ActionContext) async throws -> Result {
        let remote = options.remote ?? "origin"
        logger.info("Pushing to \(remote)")

        let git = GitCLI(context: context.shell)
        let pushOutput = try await git.push(remote: remote).run()

        if options.pushTags == true {
            _ = try await git.pushTags(remote: remote).run()
        }

        return Result(output: pushOutput.stdout)
    }

    private func getLog(context: ActionContext) async throws -> Result {
        let output = try await GitCLI(context: context.shell).logOneline(limit: 20).run()
        return Result(output: output.stdout)
    }

    private func getHash(context: ActionContext) async throws -> Result {
        let output = try await GitCLI(context: context.shell).currentHEAD().run()
        return Result(output: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

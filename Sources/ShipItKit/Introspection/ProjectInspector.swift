import Foundation
import SwiftyShell

public struct ProjectInspector: Sendable {
    private let rootPath: String
    private let shell: ShellContext

    public init(rootPath: String = FileManager.default.currentDirectoryPath, shell: ShellContext = ShellContext()) {
        self.rootPath = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL.path
        self.shell = shell
    }

    public func inspect() async throws -> ProjectInspection {
        let fileManager = FileManager.default
        let containers = discoverXcodeContainers(fileManager: fileManager)
        let preferredContainer = preferredContainer(from: containers)
        let schemes = try await inspectSchemes(in: preferredContainer)
        let suggestedAppConfig = suggestedAppConfig(from: preferredContainer, schemes: schemes)

        var warnings: [String] = []
        if containers.isEmpty {
            warnings.append("No .xcworkspace or .xcodeproj files were found under the selected path.")
        }
        if !containers.isEmpty && schemes.isEmpty {
            warnings.append("No shared schemes were discovered for the preferred Xcode container.")
        }
        if containers.count > 1 {
            warnings.append("Multiple Xcode containers were found. Review the suggested workspace/project before using generated config.")
        }

        return ProjectInspection(
            rootPath: rootPath,
            xcodeContainers: containers,
            preferredContainer: preferredContainer,
            schemes: schemes,
            suggestedAppConfig: suggestedAppConfig,
            existingShipfiles: discoverFiles(named: ["Shipfile.yml", "Shipfile.example.yml"], suffixes: ["yml", "yaml"], matcher: { $0.lastPathComponent.hasPrefix("Shipfile") }, fileManager: fileManager),
            fastlaneFiles: discoverKnownFiles(["fastlane/Fastfile", "fastlane/Appfile"], fileManager: fileManager),
            ciFiles: discoverKnownFiles([".github/workflows", "bitrise.yml", ".gitlab-ci.yml"], fileManager: fileManager),
            warnings: warnings
        )
    }

    private func discoverXcodeContainers(fileManager: FileManager) -> [ProjectInspection.XcodeContainer] {
        let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: rootPath), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var containers: [ProjectInspection.XcodeContainer] = []

        while let url = enumerator?.nextObject() as? URL {
            if shouldSkip(url: url) {
                enumerator?.skipDescendants()
                continue
            }

            if url.pathExtension == "xcworkspace" {
                containers.append(.init(kind: "workspace", path: relativePath(for: url.path)))
                enumerator?.skipDescendants()
            } else if url.pathExtension == "xcodeproj" {
                containers.append(.init(kind: "project", path: relativePath(for: url.path)))
                enumerator?.skipDescendants()
            }
        }

        return containers.sorted {
            if $0.kind != $1.kind {
                return $0.kind == "workspace"
            }
            return $0.path < $1.path
        }
    }

    private func preferredContainer(from containers: [ProjectInspection.XcodeContainer]) -> ProjectInspection.XcodeContainer? {
        containers.first(where: { $0.kind == "workspace" }) ?? containers.first
    }

    private func inspectSchemes(in container: ProjectInspection.XcodeContainer?) async throws -> [ProjectInspection.SchemeSummary] {
        guard let container else { return [] }

        let output = try await xcodebuild(for: container)
            .option(.list)
            .run()

        guard output.exitCode == 0 else { return [] }
        let schemes = parseSchemes(from: output.stdout)

        return try await withThrowingTaskGroup(of: ProjectInspection.SchemeSummary.self) { group in
            for scheme in schemes {
                group.addTask {
                    let buildSettings = try await buildSettings(for: scheme, in: container)
                    return ProjectInspection.SchemeSummary(
                        name: scheme,
                        containerPath: container.path,
                        bundleID: buildSettings["PRODUCT_BUNDLE_IDENTIFIER"],
                        teamID: buildSettings["DEVELOPMENT_TEAM"],
                        likelyRunnable: isLikelyRunnableScheme(scheme)
                    )
                }
            }

            var summaries: [ProjectInspection.SchemeSummary] = []
            for try await summary in group {
                summaries.append(summary)
            }
            return summaries.sorted { $0.name < $1.name }
        }
    }

    private func buildSettings(for scheme: String, in container: ProjectInspection.XcodeContainer) async throws -> [String: String] {
        let output = try await xcodebuild(for: container)
            .option(.scheme(scheme))
            .option(.showBuildSettings)
            .run()

        // Note: SubprocessExecutor already throws ShellError.exitFailure before returning a
        // non-zero exit code in production, so this guard is only reachable via mock executors
        // in tests that return a non-zero exit code without throwing.
        guard output.exitCode == 0 else { return [:] }
        return output.stdout.split(separator: "\n").reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    private func xcodebuild(for container: ProjectInspection.XcodeContainer) -> XcodeBuild {
        let absoluteContainerPath = URL(fileURLWithPath: rootPath).appendingPathComponent(container.path).path
        let option: XcodeBuildOption = container.kind == "workspace"
            ? .workspace(absoluteContainerPath)
            : .project(absoluteContainerPath)
        return XcodeBuild(context: shell).option(option)
    }

    private func parseSchemes(from output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var inSchemesSection = false
        var schemes: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Schemes:" {
                inSchemesSection = true
                continue
            }

            if inSchemesSection {
                if trimmed.isEmpty {
                    if !schemes.isEmpty {
                        break
                    }
                    continue
                }

                if line.hasPrefix("        ") || line.hasPrefix("    ") {
                    schemes.append(trimmed)
                    continue
                }

                break
            }
        }

        return schemes
    }

    private func suggestedAppConfig(
        from container: ProjectInspection.XcodeContainer?,
        schemes: [ProjectInspection.SchemeSummary]
    ) -> ProjectInspection.SuggestedAppConfig {
        guard let container else {
            return .init()
        }

        let baseName = URL(fileURLWithPath: container.path).deletingPathExtension().lastPathComponent
        let preferredScheme = schemes.first(where: { $0.name == baseName && $0.likelyRunnable })
            ?? schemes.first(where: { $0.likelyRunnable })
            ?? schemes.first

        return .init(
            workspace: container.kind == "workspace" ? container.path : nil,
            project: container.kind == "project" ? container.path : nil,
            scheme: preferredScheme?.name,
            bundleID: preferredScheme?.bundleID,
            teamID: preferredScheme?.teamID
        )
    }

    private func discoverKnownFiles(_ relativePaths: [String], fileManager: FileManager) -> [String] {
        relativePaths.compactMap { relativePath in
            let absolute = URL(fileURLWithPath: rootPath).appendingPathComponent(relativePath).path
            return fileManager.fileExists(atPath: absolute) ? relativePath : nil
        }
    }

    private func discoverFiles(
        named names: [String],
        suffixes: [String],
        matcher: (URL) -> Bool,
        fileManager: FileManager
    ) -> [String] {
        let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: rootPath), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var matches: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            if shouldSkip(url: url) {
                enumerator?.skipDescendants()
                continue
            }
            if names.contains(url.lastPathComponent) || suffixes.contains(url.pathExtension.lowercased()) && matcher(url) {
                matches.append(relativePath(for: url.path))
            }
        }

        return matches.sorted()
    }

    private func relativePath(for absolutePath: String) -> String {
        let normalizedRootPath = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedFilePath = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().standardizedFileURL.path

        guard normalizedFilePath.hasPrefix(normalizedRootPath + "/") else {
            return URL(fileURLWithPath: normalizedFilePath).lastPathComponent
        }

        return String(normalizedFilePath.dropFirst(normalizedRootPath.count + 1))
    }

    private func shouldSkip(url: URL) -> Bool {
        let skippedNames: Set<String> = [".git", ".build", "DerivedData", "node_modules"]
        return skippedNames.contains(url.lastPathComponent)
    }

    private func isLikelyRunnableScheme(_ scheme: String) -> Bool {
        let lowered = scheme.lowercased()
        return !lowered.contains("test")
            && !lowered.contains("uitest")
            && !lowered.contains("package")
            && !lowered.contains("watch")
            && !lowered.contains("clip")
    }
}

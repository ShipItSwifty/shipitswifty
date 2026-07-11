#if os(macOS)
/// The Xcode container selected for an `xcodebuild` operation.
///
/// Use this type instead of adding raw `-project` or `-workspace` options when
/// the container is selected dynamically. A command has at most one typed container.
public enum XcodeBuildContainer: Sendable, Equatable, Hashable {
    /// An `.xcodeproj` container.
    case project(String)
    /// An `.xcworkspace` container.
    case workspace(String)

    var option: XcodeBuildOption {
        switch self {
        case .project(let path):
            .project(path)
        case .workspace(let path):
            .workspace(path)
        }
    }
}

/// One framework or library supplied to ``XcodeBuild/createXCFramework(inputs:output:allowInternalDistribution:)``.
public enum XcodeBuildXCFrameworkInput: Sendable, Equatable, Hashable {
    /// A framework input, optionally selected from an archive and followed by its debug symbols.
    case framework(path: String, archivePath: String? = nil, debugSymbols: [String] = [])
    /// A library input, optionally selected from an archive, with associated headers and debug symbols.
    case library(
        path: String,
        headersPath: String? = nil,
        archivePath: String? = nil,
        debugSymbols: [String] = []
    )

    var arguments: [String] {
        switch self {
        case .framework(let path, let archivePath, let debugSymbols):
            var arguments = archivePath.map { ["-archive", $0] } ?? []
            arguments += ["-framework", path]
            arguments += debugSymbols.flatMap { ["-debug-symbols", $0] }
            return arguments
        case .library(let path, let headersPath, let archivePath, let debugSymbols):
            var arguments = archivePath.map { ["-archive", $0] } ?? []
            arguments += ["-library", path]
            if let headersPath {
                arguments += ["-headers", headersPath]
            }
            arguments += debugSymbols.flatMap { ["-debug-symbols", $0] }
            return arguments
        }
    }
}

enum XcodeBuildOperation: Sendable, Equatable {
    case build(clean: Bool)
    case test
    case archive(path: String?)
    case exportArchive(archivePath: String, exportPath: String?, exportOptionsPlist: String)
    case showBuildSettings(json: Bool)
    case showDestinations
    case createXCFramework(inputs: [XcodeBuildXCFrameworkInput], output: String, allowInternalDistribution: Bool)

    var prefixArguments: [String] {
        switch self {
        case .exportArchive(let archivePath, let exportPath, let exportOptionsPlist):
            var arguments = ["-exportArchive", "-archivePath", archivePath]
            if let exportPath {
                arguments += ["-exportPath", exportPath]
            }
            arguments += ["-exportOptionsPlist", exportOptionsPlist]
            return arguments
        case .createXCFramework(let inputs, let output, let allowInternalDistribution):
            var arguments = ["-create-xcframework"]
            arguments += inputs.flatMap(\.arguments)
            arguments += ["-output", output]
            if allowInternalDistribution {
                arguments.append("-allow-internal-distribution")
            }
            return arguments
        default:
            return []
        }
    }

    var argumentsAfterOptions: [String] {
        switch self {
        case .archive(let path):
            path.map { ["-archivePath", $0] } ?? []
        case .showBuildSettings(let json):
            json ? ["-showBuildSettings", "-json"] : ["-showBuildSettings"]
        case .showDestinations:
            ["-showdestinations"]
        default:
            []
        }
    }

    var buildActions: [String] {
        switch self {
        case .build(let clean):
            clean ? ["clean", "build"] : ["build"]
        case .test:
            ["test"]
        case .archive:
            ["archive"]
        default:
            []
        }
    }
}
#endif

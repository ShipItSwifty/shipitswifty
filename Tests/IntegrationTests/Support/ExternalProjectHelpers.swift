import Foundation
import Testing

enum ExternalProjectPaths {
    static var flutterProject: URL? {
        environmentURL("SHIPIT_EXTERNAL_FLUTTER_PROJECT")
    }

    static var reactNativeProject: URL? {
        environmentURL("SHIPIT_EXTERNAL_RN_PROJECT")
    }

    private static func environmentURL(_ key: String) -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw)
    }
}

func makeTempShipfile(
    prefix: String,
    directory: URL,
    contents: String
) throws -> URL {
    let url =
        directory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).yml")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func assertExternalProjectExists(_ url: URL?, envKey: String) throws -> URL {
    guard let url else {
        throw ExternalProjectError.notConfigured(envKey: envKey)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ExternalProjectError.missingProject(path: url.path)
    }
    return url
}

func shipfileForExternalFlutterProject(at projectURL: URL) -> String {
    """
    platform: ios

    ios:
      build_system: flutter

    android:
      build_system: flutter
    """
}

func shipfileForExternalReactNativeProject(at projectURL: URL) -> String {
    let iosProject = detectReactNativeIOSProject(in: projectURL)
    let appBlock =
        iosProject.map {
            """
            app:
              project: \($0.project)
              scheme: \($0.scheme)
            """
        } ?? ""

    return """
        platform: ios
        \(appBlock)

        ios:
          build_system: react_native

        android:
          build_system: react_native
          module: app
          gradle_project_dir: ./android
          gradlew_path: ./android/gradlew

        """
}

private struct ReactNativeIOSProjectInfo: Sendable {
    let project: String
    let scheme: String
}

private func detectReactNativeIOSProject(in projectURL: URL) -> ReactNativeIOSProjectInfo? {
    let iosDirectory = projectURL.appendingPathComponent("ios")
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: iosDirectory.path) else {
        return nil
    }
    return entries.first(where: { $0.hasSuffix(".xcodeproj") }).map {
        ReactNativeIOSProjectInfo(
            project: "ios/\($0)",
            scheme: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        )
    }
}

func externalProjectHasNodeModules(_ projectURL: URL) -> Bool {
    FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("node_modules").path)
}

enum ExternalProjectError: Error, CustomStringConvertible, Sendable {
    case notConfigured(envKey: String)
    case missingProject(path: String)

    var description: String {
        switch self {
        case .notConfigured(let envKey):
            return "Missing required environment variable: \(envKey)"
        case .missingProject(let path):
            return "External project not found at '\(path)'"
        }
    }
}

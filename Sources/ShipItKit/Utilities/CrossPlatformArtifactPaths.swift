import Foundation

enum CrossPlatformArtifactPaths {
    static func flutterAAB(flavor: String? = nil, variant: String = "release") -> String {
        let normalizedVariant = variant.lowercased()
        if let flavor, !flavor.isEmpty {
            let directory = flavor + normalizedVariant.capitalized
            return "build/app/outputs/bundle/\(directory)/app-\(flavor)-\(normalizedVariant).aab"
        }
        return "build/app/outputs/bundle/\(normalizedVariant)/app-\(normalizedVariant).aab"
    }

    static func flutterAPK(flavor: String? = nil, variant: String = "release") -> String {
        let normalizedVariant = variant.lowercased()
        if let flavor, !flavor.isEmpty {
            return "build/app/outputs/flutter-apk/app-\(flavor)-\(normalizedVariant).apk"
        }
        return "build/app/outputs/flutter-apk/app-\(normalizedVariant).apk"
    }

    static func reactNativeAAB(variant: String = "release") -> String {
        let normalizedVariant = variant.lowercased()
        return "android/app/build/outputs/bundle/\(normalizedVariant)/app-\(normalizedVariant).aab"
    }

    static func reactNativeAPK(variant: String = "release") -> String {
        let normalizedVariant = variant.lowercased()
        return "android/app/build/outputs/apk/\(normalizedVariant)/app-\(normalizedVariant).apk"
    }

    static func gradleTaskName(prefix: String, flavor: String? = nil, variant: String = "release") -> String {
        let variantName: String
        if let flavor, !flavor.isEmpty {
            variantName = flavor + variant.capitalized
        } else {
            variantName = variant
        }
        return prefix + variantName.prefix(1).uppercased() + variantName.dropFirst()
    }

    static func locateExportedIPA(context: ActionContext, fileManager: FileManager = .default) -> String? {
        let workingDirectory = context.shell.workingDirectory ?? fileManager.currentDirectoryPath
        let outputDirectory = context.config.exportOutputDirectory ?? "./build/export"
        if let ipa = firstIPA(in: outputDirectory, relativeTo: workingDirectory, fileManager: fileManager) {
            return ipa
        }

        guard context.config.iosBuildSystem == .flutter else { return nil }
        return firstIPA(in: "build/ios/ipa", relativeTo: workingDirectory, fileManager: fileManager)
    }

    private static func firstIPA(in directory: String, relativeTo workingDirectory: String, fileManager: FileManager) -> String? {
        let resolvedDirectory: String
        if (directory as NSString).isAbsolutePath {
            resolvedDirectory = directory
        } else {
            resolvedDirectory = (workingDirectory as NSString).appendingPathComponent(directory)
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: resolvedDirectory) else {
            return nil
        }
        guard let ipaName = contents.sorted().first(where: { $0.hasSuffix(".ipa") }) else {
            return nil
        }
        return (resolvedDirectory as NSString).appendingPathComponent(ipaName)
    }
}

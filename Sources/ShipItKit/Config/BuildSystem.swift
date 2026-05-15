import Foundation

/// The build system that produces the native artifact for a given target platform.
///
/// `BuildSystem` is orthogonal to ``Platform``: a single source tree can target both
/// `.ios` and `.android` while being built by a cross-platform tool such as Flutter,
/// React Native, or Kotlin Multiplatform. Native (pure Swift / pure Android-Gradle)
/// projects use ``BuildSystem/native``.
///
/// The value is configured under the `ios:` or `android:` Shipfile block via the
/// `build_system:` key, or via the `SHIPIT_IOS__BUILD_SYSTEM` /
/// `SHIPIT_ANDROID__BUILD_SYSTEM` environment variables. When unset, ``ConfigResolver``
/// auto-detects it from project files (e.g. `pubspec.yaml` → `.flutter`,
/// `kotlin("multiplatform")` in `build.gradle.kts` → `.kmp`).
///
/// ## Usage
/// ```yaml
/// ios:
///   build_system: kmp        # native (default) | flutter | react_native | kmp
///   scheme: iosApp
/// android:
///   build_system: kmp
///   module: androidApp
/// ```
///
/// ## Auto-detection rules
///
/// | Project file detected                                             | Build system    |
/// |-------------------------------------------------------------------|-----------------|
/// | `pubspec.yaml` with a `flutter:` key                              | `.flutter`      |
/// | `package.json` containing `react-native` dependency               | `.reactNative`  |
/// | `build.gradle.kts` declaring `kotlin("multiplatform")` plugin     | `.kmp`          |
/// | none of the above                                                 | `.native`       |
public enum BuildSystem: String, Codable, Sendable, CaseIterable {
    /// Pure native build (Swift + xcodebuild for iOS, Kotlin/Java + Gradle for Android).
    case native

    /// Flutter — `flutter build` produces `.app` / `.ipa` on iOS and `.apk` / `.aab` on Android.
    case flutter

    /// React Native — Metro bundles JS, then xcodebuild (iOS) or Gradle (Android) produces the native artifact.
    case reactNative = "react_native"

    /// Kotlin Multiplatform — Gradle handles the Android target and produces an iOS framework
    /// that is consumed by an Xcode wrapper project.
    case kmp
}

extension BuildSystem {
    /// Auto-detects the build system from project files in the given directory.
    ///
    /// Detection precedence (first match wins):
    /// 1. `pubspec.yaml` containing a `flutter:` key → ``BuildSystem/flutter``
    /// 2. `package.json` declaring a `react-native` dependency → ``BuildSystem/reactNative``
    /// 3. `build.gradle.kts` (or `build.gradle`) applying `kotlin("multiplatform")` or
    ///    `org.jetbrains.kotlin.multiplatform` → ``BuildSystem/kmp``
    /// 4. otherwise `nil`, meaning ``BuildSystem/native`` is appropriate.
    ///
    /// - Parameters:
    ///   - directoryPath: Project root to inspect.
    ///   - fileManager: File manager used for existence checks (defaults to `.default`).
    /// - Returns: The detected build system, or `nil` when no cross-platform framework is found.
    public static func autoDetect(
        in directoryPath: String,
        fileManager: FileManager = .default
    ) -> BuildSystem? {
        let root = URL(fileURLWithPath: directoryPath)

        let pubspecPath = root.appendingPathComponent("pubspec.yaml").path
        if fileManager.fileExists(atPath: pubspecPath),
            let contents = try? String(contentsOfFile: pubspecPath, encoding: .utf8),
            contents.range(of: #"(?m)^flutter:"#, options: .regularExpression) != nil
        {
            return .flutter
        }

        let packageJsonPath = root.appendingPathComponent("package.json").path
        if fileManager.fileExists(atPath: packageJsonPath),
            let data = try? Data(contentsOf: URL(fileURLWithPath: packageJsonPath)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let deps = (json["dependencies"] as? [String: Any]) ?? [:]
            let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
            if deps["react-native"] != nil || devDeps["react-native"] != nil {
                return .reactNative
            }
        }

        for gradleFile in ["build.gradle.kts", "build.gradle"] {
            let path = root.appendingPathComponent(gradleFile).path
            guard fileManager.fileExists(atPath: path),
                let contents = try? String(contentsOfFile: path, encoding: .utf8)
            else { continue }
            if contents.contains(#"kotlin("multiplatform")"#)
                || contents.contains("org.jetbrains.kotlin.multiplatform")
                || contents.contains("kotlin-multiplatform")
            {
                return .kmp
            }
        }

        return nil
    }
}

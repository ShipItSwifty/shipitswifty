import Foundation
import Testing

@testable import ShipItKit

@Suite("BuildSystem")
struct BuildSystemTests {

    // MARK: - Codable

    @Test("Raw values match the documented Shipfile keys")
    func rawValues() {
        #expect(BuildSystem.native.rawValue == "native")
        #expect(BuildSystem.flutter.rawValue == "flutter")
        #expect(BuildSystem.reactNative.rawValue == "react_native")
        #expect(BuildSystem.kmp.rawValue == "kmp")
    }

    @Test("All cases round-trip through rawValue init")
    func roundTrip() {
        for value in BuildSystem.allCases {
            #expect(BuildSystem(rawValue: value.rawValue) == value)
        }
    }

    // MARK: - Auto-detection

    @Test("autoDetect returns .flutter when pubspec.yaml has a flutter: key")
    func detectsFlutter() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        name: demo
        description: A flutter demo.
        flutter:
          uses-material-design: true
        """.write(
            to: dir.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .flutter)
    }

    @Test("autoDetect ignores pubspec.yaml without a flutter: key")
    func ignoresDartOnlyPubspec() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        name: demo
        description: A pure dart project.
        environment:
          sdk: ">=3.0.0 <4.0.0"
        """.write(
            to: dir.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == nil)
    }

    @Test("autoDetect returns .reactNative when package.json has react-native dep")
    func detectsReactNative() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        {
          "name": "demo",
          "version": "1.0.0",
          "dependencies": {
            "react": "18.2.0",
            "react-native": "0.74.0"
          }
        }
        """.write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .reactNative)
    }

    @Test("autoDetect returns .reactNative when react-native is in devDependencies")
    func detectsReactNativeInDevDependencies() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        {
          "name": "demo",
          "devDependencies": {
            "react-native": "0.74.0"
          }
        }
        """.write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .reactNative)
    }

    @Test("autoDetect ignores package.json without react-native")
    func ignoresUnrelatedPackageJson() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        {
          "name": "tooling",
          "dependencies": { "typescript": "5.0.0" }
        }
        """.write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == nil)
    }

    @Test("autoDetect returns .kmp when build.gradle.kts applies kotlin(\"multiplatform\")")
    func detectsKMPViaKotlinDsl() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        plugins {
            kotlin("multiplatform") version "1.9.0"
            id("com.android.library")
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .kmp)
    }

    @Test("autoDetect returns .kmp via the jetbrains plugin id form")
    func detectsKMPViaJetbrainsPluginId() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        plugins {
            id("org.jetbrains.kotlin.multiplatform") version "1.9.0"
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .kmp)
    }

    @Test("autoDetect returns nil for a plain Android Gradle project")
    func ignoresPlainGradle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        plugins {
            id("com.android.application")
            kotlin("android") version "1.9.0"
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == nil)
    }

    @Test("autoDetect returns nil for an empty directory")
    func returnsNilForEmptyDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(BuildSystem.autoDetect(in: dir.path) == nil)
    }

    @Test("autoDetect prefers Flutter over Gradle when both files are present")
    func flutterWinsOverGradle() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        name: demo
        flutter:
          uses-material-design: true
        """.write(
            to: dir.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        try """
        plugins {
            kotlin("multiplatform") version "1.9.0"
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .flutter)
    }

    @Test("autoDetect returns .kmp when the plugin ID is only in gradle/libs.versions.toml")
    func detectsKMPViaVersionCatalog() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // JetBrains wizard layout: the root build file only references the catalog alias,
        // so none of the plugin-ID literals appear in any build.gradle.kts.
        try """
        plugins {
            alias(libs.plugins.kotlinMultiplatform).apply(false)
            alias(libs.plugins.androidApplication).apply(false)
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        let gradleDir = dir.appendingPathComponent("gradle")
        try FileManager.default.createDirectory(at: gradleDir, withIntermediateDirectories: true)
        try """
        [versions]
        kotlin = "2.1.0"

        [plugins]
        kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
        androidApplication = { id = "com.android.application", version = "8.7.0" }
        """.write(
            to: gradleDir.appendingPathComponent("libs.versions.toml"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .kmp)
    }

    @Test("autoDetect returns .kmp when only a module-level build file applies the plugin")
    func detectsKMPViaModuleBuildFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        // Root build file with no plugin references.
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        let sharedDir = dir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        try """
        plugins {
            kotlin("multiplatform")
        }
        """.write(
            to: sharedDir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == .kmp)
    }

    @Test("autoDetect ignores a version catalog without the KMP plugin ID")
    func ignoresVersionCatalogWithoutKMP() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let gradleDir = dir.appendingPathComponent("gradle")
        try FileManager.default.createDirectory(at: gradleDir, withIntermediateDirectories: true)
        try """
        [plugins]
        androidApplication = { id = "com.android.application", version = "8.7.0" }
        kotlinAndroid = { id = "org.jetbrains.kotlin.android", version = "2.1.0" }
        """.write(
            to: gradleDir.appendingPathComponent("libs.versions.toml"),
            atomically: true,
            encoding: .utf8
        )

        #expect(BuildSystem.autoDetect(in: dir.path) == nil)
    }
}

// swift-tools-version: 6.2
// ShipItSwifty Package Manifest

import PackageDescription

let package = Package(
    name: "ShipItSwifty",
    // macOS 15+ required for full functionality (Xcode toolchain, Security framework, etc.)
    // Linux is also supported for ShipItKit core and CLI targets.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "shipit", targets: ["ShipItCLI"]),
        .library(name: "ShipItKit", targets: ["ShipItKit"]),
    ],
    dependencies: [
        // Shell execution
        .package(url: "https://github.com/maniramezan/SwiftyShell.git", from: "0.7.0"),
        // Typed tool wrappers (xcodebuild, xcrun, Gradle, adb, Flutter, …). Tracks main until 1.0.
        .package(url: "https://github.com/ShipItSwifty/cli-wrappers.git", branch: "main"),
        // Build, device, test, and inspection mechanisms shared with Amoo. Tracks main until 1.0.
        .package(url: "https://github.com/ShipItSwifty/mobile-kits.git", branch: "main"),
        // DocC generation command plugin
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        // App Store Connect API client + Xcode Cloud read API (extracted from this repo).
        // Includes the 0.1.6 write-encoding fix: earlier versions sent snake_case
        // POST/PATCH keys that ASC ignored in AppStoreReleaseService writes.
        // Pin the MCP target-conflict fix pending a patch release: app-store-connect-mcp#19.
        .package(url: "https://github.com/ShipItSwifty/app-store-connect-mcp.git", revision: "912a98974bba73182ac63d9f4b5c26b1d45bd395"),
        // Google service-account auth + Google Play Developer API client (extracted from this repo).
        // Includes the fixes through 0.1.3 for decoding draft releases in listTracks
        // and the live-verified write encoding.
        .package(url: "https://github.com/ShipItSwifty/google-play-store-mcp.git", from: "0.2.1"),
        // YAML config parsing
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),
        // Crypto for code signing operations
        .package(url: "https://github.com/apple/swift-crypto", from: "4.4.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
        // Shared test helpers (test targets only)
        .package(url: "https://github.com/maniramezan/SwiftTestCommons.git", from: "0.3.0"),
    ],
    targets: [
        // MARK: - ShipItKit

        .target(
            name: "ShipItKit",
            dependencies: [
                .product(name: "MobileCore", package: "mobile-kits"),
                .product(name: "MobileBuild", package: "mobile-kits"),
                .product(name: "MobileDevices", package: "mobile-kits"),
                .product(name: "MobileProject", package: "mobile-kits"),
                .product(name: "MobileTesting", package: "mobile-kits"),
                .product(name: "AdbKit", package: "cli-wrappers"),
                .product(name: "AndroidCLIKit", package: "cli-wrappers"),
                .product(name: "BundletoolKit", package: "cli-wrappers"),
                .product(name: "EmulatorKit", package: "cli-wrappers"),
                .product(name: "FlutterKit", package: "cli-wrappers"),
                .product(name: "FrameitKit", package: "cli-wrappers"),
                .product(name: "GradleKit", package: "cli-wrappers"),
                .product(name: "PlutilKit", package: "cli-wrappers"),
                .product(name: "ReactNativeKit", package: "cli-wrappers"),
                .product(name: "SecurityKit", package: "cli-wrappers"),
                .product(name: "SwiftPMKit", package: "cli-wrappers"),
                .product(name: "XcodeBuildKit", package: "cli-wrappers"),
                .product(name: "XcodeGenKit", package: "cli-wrappers"),
                .product(name: "XcrunKit", package: "cli-wrappers"),
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AppStoreConnectKit", package: "app-store-connect-mcp"),
                .product(name: "AppStoreConnectUploadKit", package: "app-store-connect-mcp"),
                .product(name: "GoogleAuthKit", package: "google-play-store-mcp"),
                .product(name: "GooglePlayKit", package: "google-play-store-mcp"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // MARK: - CLI

        .executableTarget(
            name: "ShipItCLI",
            dependencies: [
                .product(name: "MobileCore", package: "mobile-kits"),
                .product(name: "MobileTesting", package: "mobile-kits"),
                "ShipItKit",
                .product(name: "AndroidCLIKit", package: "cli-wrappers"),
                .product(name: "ReactNativeKit", package: "cli-wrappers"),
                .product(name: "SecurityKit", package: "cli-wrappers"),
                .product(name: "XcodeBuildKit", package: "cli-wrappers"),
                .product(name: "XcrunKit", package: "cli-wrappers"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/CLI"
        ),

        // MARK: - Tests

        .testTarget(
            name: "ShipItKitTests",
            dependencies: [
                .product(name: "MobileCore", package: "mobile-kits"),
                .product(name: "MobileTesting", package: "mobile-kits"),
                "ShipItKit",
                .product(name: "SwiftPMKit", package: "cli-wrappers"),
                .product(name: "XcodeBuildKit", package: "cli-wrappers"),
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "AppStoreConnectKit", package: "app-store-connect-mcp"),
                .product(name: "GoogleAuthKit", package: "google-play-store-mcp"),
                .product(name: "GooglePlayKit", package: "google-play-store-mcp"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "TestCommons", package: "SwiftTestCommons"),
            ],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                "ShipItCLI",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "MobileCore", package: "mobile-kits"),
                "ShipItKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Tests/IntegrationTests",
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

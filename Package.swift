// swift-tools-version: 6.0
// ShipItSwifty Package Manifest

import PackageDescription

let package = Package(
    name: "ShipItSwifty",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "shipit", targets: ["CLI"]),
        .library(name: "ShipItKit", targets: ["ShipItKit"]),
        .library(name: "XcodeBuildKit", targets: ["XcodeBuildKit"]),
        .library(name: "GradleKit", targets: ["GradleKit"]),
        .library(name: "XcodeGenKit", targets: ["XcodeGenKit"]),
    ],
    dependencies: [
        // Shell execution
        .package(url: "https://github.com/maniramezan/swiftyshell", from: "0.1.0"),
        // DocC generation command plugin
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        // JWT for App Store Connect auth
        .package(url: "https://github.com/vapor/jwt-kit", from: "5.4.0"),
        // YAML config parsing
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),
        // Crypto for code signing operations
        .package(url: "https://github.com/apple/swift-crypto", from: "4.4.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    ],
    targets: [
        // MARK: - Reusable tool libraries

        .target(
            name: "XcodeBuildKit",
            dependencies: [
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .target(
            name: "GradleKit",
            dependencies: [
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .target(
            name: "XcodeGenKit",
            dependencies: [
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),

        // MARK: - ShipItKit (depends on tool libraries)

        .target(
            name: "ShipItKit",
            dependencies: [
                "XcodeBuildKit",
                "GradleKit",
                "XcodeGenKit",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // MARK: - CLI

        .executableTarget(
            name: "CLI",
            dependencies: [
                "ShipItKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "XcodeBuildKitTests",
            dependencies: [
                "XcodeBuildKit",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .testTarget(
            name: "GradleKitTests",
            dependencies: [
                "GradleKit",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .testTarget(
            name: "XcodeGenKitTests",
            dependencies: [
                "XcodeGenKit",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .testTarget(
            name: "ShipItKitTests",
            dependencies: [
                "ShipItKit",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                "CLI",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "ShipItKit",
            ],
            path: "Tests/IntegrationTests",
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0
// ShipItSwifty Package Manifest

import PackageDescription

let package = Package(
    name: "ShipItSwifty",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "shipit", targets: ["CLI"]),
        .library(name: "ShipItKit", targets: ["ShipItKit"]),
    ],
    dependencies: [
        // Shell execution
        .package(url: "https://github.com/maniramezan/swiftyshell", branch: "main"),
        // DocC generation command plugin
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.4.5"),
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
        .target(
            name: "ShipItKit",
            dependencies: [
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "CLI",
            dependencies: [
                "ShipItKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
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

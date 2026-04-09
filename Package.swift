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
        // Shell execution — local path while SwiftyShell is co-developed (swap to remote when published)
        .package(path: "../SwiftyShell"),
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // JWT for App Store Connect auth
        .package(url: "https://github.com/vapor/jwt-kit", from: "5.0.0"),
        // YAML config parsing
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        // Crypto for code signing operations
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ShipItKit",
            dependencies: [
                .product(name: "SwiftyShell", package: "SwiftyShell"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Crypto", package: "swift-crypto"),
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
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                "CLI",
                .product(name: "SwiftyShell", package: "SwiftyShell"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

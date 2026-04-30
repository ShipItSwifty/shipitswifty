// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuildTimingPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BuildTimingPlugin", targets: ["BuildTimingPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/shipitswifty/shipitswifty", branch: "main")
    ],
    targets: [
        .target(
            name: "BuildTimingPlugin",
            dependencies: [
                .product(name: "ShipItKit", package: "shipitswifty")
            ]
        ),
        .testTarget(
            name: "BuildTimingPluginTests",
            dependencies: [
                "BuildTimingPlugin",
                .product(name: "ShipItKit", package: "shipitswifty"),
                .product(name: "SwiftyShell", package: "swiftyshell"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

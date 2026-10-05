// swift-tools-version: 6.0
import PackageDescription

// A deliberately tiny package whose tests have *scripted* outcomes, so integration tests can run the real
// `shipit` binary against it and assert exactly what ShipIt reports. See SampleTests.swift for the controls.
let package = Package(
    name: "Sample",
    products: [.library(name: "Sample", targets: ["Sample"])],
    targets: [
        .target(name: "Sample"),
        .testTarget(name: "SampleTests", dependencies: ["Sample"]),
    ],
    swiftLanguageModes: [.v6]
)

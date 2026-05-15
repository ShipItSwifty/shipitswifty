# SwiftPM scripting

Use ShipItSwifty as regular Swift packages when you want typed release scripts instead of the `shipit` binary.

## Choosing a library

| Library | Use when |
|---|---|
| `GradleKit` | You only need typed Gradle, adb, emulator, or bundletool commands. |
| `XcodeBuildKit` | You only need typed `xcodebuild` and destination discovery. |
| ``ShipItKit`` | You want release-domain actions, workflows, config resolution, KMP build-system handling, versioning, or distribution clients. |

`ShipItKit` re-exports the tool libraries, so scripts that import `ShipItKit` can also use `Gradle`, `GradleTask`, and `XcodeBuild` directly.

## Gradle-only script

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReleaseScripts",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/maniramezan/ShipItSwifty.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "android-release",
            dependencies: [
                .product(name: "GradleKit", package: "ShipItSwifty")
            ]
        )
    ]
)
```

```swift
// Sources/android-release/main.swift
import GradleKit

let output = try await Gradle()
    .projectDir(".")
    .task(GradleTask.bundleRelease.qualified(module: "androidApp"))
    .flag(.noDaemon)
    .flag(.configurationCache)
    .run()

print(output.stdout)
```

## ShipItKit workflow script

```swift
// Package.swift target dependency
.product(name: "ShipItKit", package: "ShipItSwifty")
```

```swift
import ShipItKit

let config = try await ConfigResolver().resolve(
    cliOptions: CLIOptions(platform: .ios),
    shipfilePath: "./Shipfile.yml"
)
#if os(macOS)
let context = ActionContext(
    shell: ShellContext(),
    logger: Logger.forType(subsystem: "ReleaseScripts", ActionContext.self),
    config: config,
    appStoreConnect: AppStoreConnectClient(
        keyID: config.ascKeyID ?? "",
        issuerID: config.ascIssuerID ?? "",
        privateKeyData: config.ascPrivateKeyData ?? Foundation.Data()
    ),
    platform: .ios
)

_ = try await BuildAction().run(
    with: .init(scheme: config.appScheme, configuration: .release),
    context: context
)
#endif
```

## KMP notes

KMP support lives in ShipItKit because it depends on resolved Shipfile settings. For direct scripts, set these fields in `Shipfile.yml` or construct ``ResolvedConfig`` with the matching values:

- ``ResolvedConfig/kmpSharedModule``
- ``ResolvedConfig/kmpBuildTarget``
- ``ResolvedConfig/kmpArchiveTarget``
- ``ResolvedConfig/kmpTestTask``
- ``ResolvedConfig/gradleProjectDir``
- ``ResolvedConfig/gradlewPath``

## Topics

### ShipItKit scripting

- ``ConfigResolver``
- ``ResolvedConfig``
- ``ActionContext``
- ``BuildAction``
- ``ArchiveAction``
- ``TestAction``

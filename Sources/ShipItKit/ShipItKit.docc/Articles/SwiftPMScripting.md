# SwiftPM scripting

Use ShipItSwifty as regular Swift packages when you want typed release scripts instead of the `shipit` binary.

## Choosing a library

| Library | Use when |
|---|---|
| `GradleKit` | You only need typed Gradle, adb, emulator, or bundletool commands. |
| `AndroidCLIKit` | You need typed access to Google's preview AndroidCLI command families. |
| `XcodeBuildKit` | You only need typed `xcodebuild` and destination discovery. |
| ``ShipItKit`` | You want release-domain actions, workflows, config resolution, KMP build-system handling, versioning, or distribution clients. |

`ShipItKit` re-exports the tool libraries, so scripts that import `ShipItKit` can also use `Gradle`, `GradleTask`, `AndroidCLI`, and `XcodeBuild` directly.

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

## AndroidCLIKit script

AndroidCLIKit is independent of the Gradle build pipeline and can be used without ShipItKit:

```swift
// Package.swift target dependency
.product(name: "AndroidCLIKit", package: "ShipItSwifty")
```

```swift
import AndroidCLIKit

let project = try await AndroidCLI(
    executablePath: "android",
    sdkPath: "/opt/android-sdk"
)
.describe(arguments: ["--json"])
.run()

let emulators = try await AndroidCLI()
    .emulatorList(arguments: ["--long"])
    .run()

print(project.stdout)
print(emulators.stdout)
```

The raw-argument builder is available for preview-version drift, while typed methods cover AndroidCLI 1.0 command families. AndroidCLI itself may report basic command/option telemetry; consult Google's AndroidCLI documentation before enabling it in sensitive environments.

## XcodeBuildKit script

Operation methods place `xcodebuild` actions and standalone modes in the correct
part of the command. Selecting a project or workspace replaces the previous typed
container, so scripts cannot accidentally emit both.

```swift
import XcodeBuildKit

let archive = try await XcodeBuild()
    .workspace("App.xcworkspace")
    .option(.scheme("App"))
    .option(.configuration("Release"))
    .buildSetting("CODE_SIGN_STYLE", "Automatic")
    .archive(path: "./build/App.xcarchive")
    .run()

let exported = try await XcodeBuild()
    .exportArchive(
        archivePath: "./build/App.xcarchive",
        exportPath: "./build/export",
        exportOptionsPlist: "./ExportOptions.plist"
    )
    .run()
```

Use `.build(clean:)`, `.test()`, `.showBuildSettings(json:)`,
`.showDestinations()`, and `.createXCFramework(inputs:output:)` for the other
modeled operations. Raw `.option(...)` and `.trailingArgument(...)` builders are
still available for unsupported or newly introduced `xcodebuild` arguments.

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

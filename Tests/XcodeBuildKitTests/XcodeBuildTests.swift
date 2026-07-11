#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import XcodeBuildKit

struct XcodeBuildTests {
    @Test func buildsTypedCommandWithTrailingArgumentsAndSettings() {
        let command = XcodeBuild()
            .option(.project("App.xcodeproj"))
            .option(.scheme("App"))
            .option(.sdk("iphonesimulator"))
            .buildSetting("SWIFT_VERSION", "6.1")
            .trailingArgument("build")
            .command()

        #expect(command.executableName == "xcodebuild")
        #expect(
            command.arguments == [
                "-project", "App.xcodeproj",
                "-scheme", "App",
                "-sdk", "iphonesimulator",
                "SWIFT_VERSION=6.1",
                "build",
            ])
    }

    @Test func supportsRecursiveCreateXCFrameworkOptions() {
        let command = XcodeBuild()
            .option(.createXCFramework)
            .option(.framework("/tmp/Foo.framework"))
            .option(.debugSymbols("/tmp/Foo.framework.dSYM"))
            .option(.output("/tmp/Foo.xcframework"))
            .option(.allowInternalDistribution)
            .command()

        #expect(
            command.arguments == [
                "-create-xcframework",
                "-framework", "/tmp/Foo.framework",
                "-debug-symbols", "/tmp/Foo.framework.dSYM",
                "-output", "/tmp/Foo.xcframework",
                "-allow-internal-distribution",
            ])
    }

    @Test func operationBuildersPlaceActionsAfterBuildSettings() {
        let build = XcodeBuild()
            .project("App.xcodeproj")
            .option(.scheme("App"))
            .buildSetting("SWIFT_VERSION", "6")
            .build(clean: true)
            .command()
        let test = XcodeBuild().workspace("App.xcworkspace").option(.scheme("App")).test().command()
        let archive = XcodeBuild()
            .option(.scheme("App"))
            .buildSetting("SKIP_INSTALL", "NO")
            .archive(path: "/tmp/App.xcarchive")
            .command()

        #expect(
            build.arguments == [
                "-project", "App.xcodeproj", "-scheme", "App", "SWIFT_VERSION=6", "clean", "build",
            ])
        #expect(test.arguments == ["-workspace", "App.xcworkspace", "-scheme", "App", "test"])
        #expect(
            archive.arguments == [
                "-scheme", "App", "-archivePath", "/tmp/App.xcarchive", "SKIP_INSTALL=NO", "archive",
            ])
    }

    @Test func typedContainerSelectionIsExclusive() {
        let command = XcodeBuild()
            .project("Old.xcodeproj")
            .workspace("App.xcworkspace")
            .project("App.xcodeproj")
            .build()
            .command()

        #expect(command.arguments == ["-project", "App.xcodeproj", "build"])
    }

    @Test func buildsInspectionAndExportOperations() {
        let settings = XcodeBuild().project("App.xcodeproj").showBuildSettings(json: true).command()
        let destinations = XcodeBuild().option(.scheme("App")).showDestinations().command()
        let export = XcodeBuild()
            .option(.allowProvisioningUpdates)
            .exportArchive(
                archivePath: "/tmp/App.xcarchive",
                exportPath: "/tmp/export",
                exportOptionsPlist: "/tmp/ExportOptions.plist"
            )
            .command()

        #expect(settings.arguments == ["-project", "App.xcodeproj", "-showBuildSettings", "-json"])
        #expect(destinations.arguments == ["-scheme", "App", "-showdestinations"])
        #expect(
            export.arguments == [
                "-exportArchive", "-archivePath", "/tmp/App.xcarchive", "-exportPath", "/tmp/export",
                "-exportOptionsPlist", "/tmp/ExportOptions.plist", "-allowProvisioningUpdates",
            ])
    }

    @Test func groupsXCFrameworkInputArguments() {
        let command = XcodeBuild()
            .createXCFramework(
                inputs: [
                    .framework(
                        path: "Foo.framework",
                        archivePath: "/tmp/Foo.xcarchive",
                        debugSymbols: ["/tmp/Foo.framework.dSYM"]
                    ),
                    .library(path: "/tmp/libBar.a", headersPath: "/tmp/include"),
                ],
                output: "/tmp/SDK.xcframework",
                allowInternalDistribution: true
            )
            .command()

        #expect(
            command.arguments == [
                "-create-xcframework",
                "-archive", "/tmp/Foo.xcarchive",
                "-framework", "Foo.framework",
                "-debug-symbols", "/tmp/Foo.framework.dSYM",
                "-library", "/tmp/libBar.a",
                "-headers", "/tmp/include",
                "-output", "/tmp/SDK.xcframework",
                "-allow-internal-distribution",
            ])
    }

    @Test func runsVersionCommand() async throws {
        let output = try await XcodeBuild()
            .option(.version)
            .run()

        #expect(output.stdout.contains("Xcode "))
        #expect(output.stdout.contains("Build version "))
        #expect(output.exitCode == 0)
    }
}
#endif

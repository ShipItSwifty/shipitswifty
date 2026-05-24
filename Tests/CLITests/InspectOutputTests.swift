import Foundation
import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("Inspect output")
struct InspectOutputTests {

    @Test("JSON includes detected build system fields")
    func jsonIncludesBuildSystemFields() {
        let inspection = ProjectInspection(
            rootPath: "/repo",
            xcodeContainers: [],
            preferredContainer: nil,
            schemes: [],
            suggestedAppConfig: .init(),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: [],
            suggestedAndroidPackageName: "com.example.app",
            detectedPlatform: .android,
            gradleFiles: ["build.gradle.kts"],
            detectedBuildSystem: .kmp,
            buildSystemFiles: ["build.gradle.kts", "settings.gradle.kts"]
        )

        let json = projectInspectionJSON(inspection)
        let object = json.objectValue ?? [:]

        #expect(object["detectedBuildSystem"] == .string("kmp"))
        #expect(object["buildSystemFiles"] == .array([.string("build.gradle.kts"), .string("settings.gradle.kts")]))
    }
}

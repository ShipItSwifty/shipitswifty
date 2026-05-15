import Foundation
import Testing

@testable import GradleKit

@Suite("GradleTask — KMP")
struct GradleTaskKMPTests {

    @Test("Provides link tasks for the standard iOS targets")
    func linkTaskStatics() {
        #expect(GradleTask.linkDebugFrameworkIosArm64.name == "linkDebugFrameworkIosArm64")
        #expect(GradleTask.linkReleaseFrameworkIosArm64.name == "linkReleaseFrameworkIosArm64")
        #expect(
            GradleTask.linkDebugFrameworkIosSimulatorArm64.name == "linkDebugFrameworkIosSimulatorArm64")
        #expect(
            GradleTask.linkReleaseFrameworkIosSimulatorArm64.name == "linkReleaseFrameworkIosSimulatorArm64"
        )
        #expect(GradleTask.linkDebugFrameworkIosX64.name == "linkDebugFrameworkIosX64")
        #expect(GradleTask.linkReleaseFrameworkIosX64.name == "linkReleaseFrameworkIosX64")
    }

    @Test("Embed-and-sign task matches the Xcode Run Script convention")
    func embedAndSignTaskName() {
        #expect(
            GradleTask.embedAndSignAppleFrameworkForXcode.name == "embedAndSignAppleFrameworkForXcode"
        )
    }

    @Test("iOS-side test tasks have the expected Gradle names")
    func iosTestTaskNames() {
        #expect(GradleTask.iosSimulatorArm64Test.name == "iosSimulatorArm64Test")
        #expect(GradleTask.iosArm64Test.name == "iosArm64Test")
        #expect(GradleTask.iosX64Test.name == "iosX64Test")
    }

    // MARK: - linkFramework helper

    @Test("linkFramework concatenates configuration and target with capitalized first letters")
    func linkFrameworkHelper() {
        #expect(
            GradleTask.linkFramework(configuration: "Release", target: "IosSimulatorArm64").name
                == "linkReleaseFrameworkIosSimulatorArm64"
        )
        #expect(
            GradleTask.linkFramework(configuration: "Debug", target: "IosArm64").name
                == "linkDebugFrameworkIosArm64"
        )
    }

    @Test("linkFramework normalizes lowercase input")
    func linkFrameworkNormalizesCasing() {
        #expect(
            GradleTask.linkFramework(configuration: "release", target: "iosArm64").name
                == "linkReleaseFrameworkIosArm64"
        )
    }

    @Test("qualified adds a Gradle module prefix")
    func qualifiedTask() {
        #expect(GradleTask.bundleRelease.qualified(module: "androidApp").name == ":androidApp:bundleRelease")
        #expect(GradleTask.iosSimulatorArm64Test.qualified(module: ":shared").name == ":shared:iosSimulatorArm64Test")
    }
}

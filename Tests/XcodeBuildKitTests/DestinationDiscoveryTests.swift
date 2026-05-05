#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import XcodeBuildKit

// MARK: - DestinationDiscovery Tests

@Suite("DestinationDiscovery")
struct DestinationDiscoveryTests {

    // MARK: - Parser

    @Test("Parses iOS Simulator destination with OS and id")
    func parsesSimulatorDestination() {
        let discoverer = DestinationDiscovery(shell: .init())
        let output = """
            Available destinations for the "MyApp" scheme:
                { platform:iOS Simulator, id:ABCD-1234, OS:18.2, name:iPhone 16 Pro }
                { platform:iOS Simulator, id:EFGH-5678, OS:18.2, name:iPhone 16 }
            """

        let destinations = discoverer.parseDestinations(from: output)

        #expect(destinations.count == 2)
        // Sorted alphabetically by name within simulators
        #expect(destinations[0].name == "iPhone 16")
        #expect(destinations[1].name == "iPhone 16 Pro")
        #expect(destinations[0].platform == "iOS Simulator")
        #expect(destinations[0].os == "18.2")
        #expect(destinations[0].udid == "EFGH-5678")
        #expect(destinations[0].isSimulator)
    }

    @Test("Parses physical device destination without OS")
    func parsesPhysicalDeviceDestination() {
        let discoverer = DestinationDiscovery(shell: .init())
        let output = """
                { platform:iOS, id:00008110-0012345600AA001E, name:My iPhone }
            """

        let destinations = discoverer.parseDestinations(from: output)

        #expect(destinations.count == 1)
        #expect(destinations[0].name == "My iPhone")
        #expect(destinations[0].platform == "iOS")
        #expect(destinations[0].os == nil)
        #expect(destinations[0].udid == "00008110-0012345600AA001E")
        #expect(!destinations[0].isSimulator)
    }

    @Test("Simulators appear before physical devices in sorted output")
    func simulatorsAppearBeforeDevices() {
        let discoverer = DestinationDiscovery(shell: .init())
        let output = """
                { platform:iOS, id:PHONE-ID, name:My iPhone }
                { platform:iOS Simulator, id:SIM-ID, OS:18.0, name:iPhone 16 }
            """

        let destinations = discoverer.parseDestinations(from: output)

        #expect(destinations.count == 2)
        #expect(destinations[0].isSimulator, "Simulator should sort before physical device")
        #expect(!destinations[1].isSimulator)
    }

    @Test("Skips destination blocks that contain an error key")
    func skipsErrorBlocks() {
        let discoverer = DestinationDiscovery(shell: .init())
        let output = """
                { platform:iOS Simulator, id:VALID-ID, OS:18.2, name:iPhone 16 }
                { platform:iOS Simulator, id:BAD-ID, OS:17.0, name:iPhone 15, error:device unavailable }
            """

        let destinations = discoverer.parseDestinations(from: output)

        #expect(destinations.count == 1)
        #expect(destinations[0].name == "iPhone 16")
    }

    @Test("Returns empty array when output has no destination blocks")
    func returnsEmptyForNoBlocks() {
        let discoverer = DestinationDiscovery(shell: .init())
        let output = "xcodebuild: error: -scheme MyApp requires a workspace or project"

        let destinations = discoverer.parseDestinations(from: output)

        #expect(destinations.isEmpty)
    }

    @Test("destinationString produces correct xcodebuild format for simulator")
    func destinationStringForSimulator() {
        let dest = XcodebuildDestination(
            platform: "iOS Simulator",
            name: "iPhone 16 Pro",
            os: "18.2",
            udid: "ABCD-1234"
        )
        #expect(dest.destinationString == "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2")
    }

    @Test("destinationString produces correct format for physical device (no OS)")
    func destinationStringForDevice() {
        let dest = XcodebuildDestination(
            platform: "iOS",
            name: "My iPhone",
            os: nil,
            udid: "00008110"
        )
        #expect(dest.destinationString == "platform=iOS,name=My iPhone")
    }
}
#endif

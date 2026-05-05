#if os(macOS)
import Foundation
import Testing

@testable import ShipItKit

@Suite("MetadataAction", .serialized)
struct MetadataActionTests {

    @Test("MetadataAction pull writes localized metadata files")
    func pullWritesMetadataFiles() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let client = makeClient(responses: [
            .json([
                "data": [
                    [
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "loc-1",
                        "attributes": [
                            "locale": "en-US",
                            "name": "Example App",
                            "subtitle": "Ship faster",
                        ],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-loc-1",
                        "attributes": [
                            "locale": "en-US",
                            "description": "Long description",
                            "keywords": "swift,ios,shipit",
                            "whatsNew": "Fresh release notes",
                        ],
                    ]
                ]
            ]),
        ])

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", MetadataAction.self),
            config: ResolvedConfig(bundleID: "com.example.app", metadataDirectory: tempDirectory.path),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await MetadataAction().run(with: .init(pull: true, directory: tempDirectory.path), context: context)

        #expect(result.operation == "pull")
        #expect(result.localesProcessed == 1)
        #expect(try String(contentsOf: tempDirectory.appendingPathComponent("en-US/name.txt"), encoding: .utf8) == "Example App")
        #expect(try String(contentsOf: tempDirectory.appendingPathComponent("en-US/subtitle.txt"), encoding: .utf8) == "Ship faster")
        #expect(
            try String(contentsOf: tempDirectory.appendingPathComponent("en-US/description.txt"), encoding: .utf8) == "Long description")
        #expect(try String(contentsOf: tempDirectory.appendingPathComponent("en-US/keywords.txt"), encoding: .utf8) == "swift,ios,shipit")
        #expect(
            try String(contentsOf: tempDirectory.appendingPathComponent("en-US/release_notes.txt"), encoding: .utf8)
                == "Fresh release notes")
    }

    @Test("MetadataAction push updates existing locale metadata")
    func pushUpdatesExistingLocale() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let localeDirectory = tempDirectory.appendingPathComponent("en-US")
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        try "New Name".write(to: localeDirectory.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
        try "New Subtitle".write(to: localeDirectory.appendingPathComponent("subtitle.txt"), atomically: true, encoding: .utf8)
        try "New Description".write(to: localeDirectory.appendingPathComponent("description.txt"), atomically: true, encoding: .utf8)
        try "swift,release".write(to: localeDirectory.appendingPathComponent("keywords.txt"), atomically: true, encoding: .utf8)
        try "Bug fixes".write(to: localeDirectory.appendingPathComponent("release_notes.txt"), atomically: true, encoding: .utf8)

        let client = makeClient(responses: [
            .json([
                "data": [
                    [
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "app-info-1"
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "loc-1",
                        "attributes": ["locale": "en-US", "name": "Old", "subtitle": "Old"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    "id": "loc-1",
                    "attributes": ["locale": "en-US", "name": "New Name", "subtitle": "New Subtitle"],
                ]
            ]),
            .json(["data": []]),
            .json([
                "data": [
                    "id": "version-loc-1",
                    "attributes": [
                        "locale": "en-US",
                        "description": "New Description",
                        "keywords": "swift,release",
                        "whatsNew": "Bug fixes",
                    ],
                ]
            ]),
        ])

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", MetadataAction.self),
            config: ResolvedConfig(bundleID: "com.example.app", metadataDirectory: tempDirectory.path),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await MetadataAction().run(with: .init(push: true, directory: tempDirectory.path), context: context)

        #expect(result.operation == "push")
        #expect(result.localesProcessed == 1)
    }

    @Test("MetadataAction creates missing app info localization")
    func pushCreatesMissingAppInfoLocalization() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let localeDirectory = tempDirectory.appendingPathComponent("fr-FR")
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        try "Nom".write(to: localeDirectory.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
        try "Sous-titre".write(to: localeDirectory.appendingPathComponent("subtitle.txt"), atomically: true, encoding: .utf8)

        let client = makeClient(responses: [
            .json([
                "data": [
                    [
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "app-info-1"
                    ]
                ]
            ]),
            .json(["data": []]),
            .json([
                "data": [
                    "id": "loc-new",
                    "attributes": ["locale": "fr-FR", "name": "Nom", "subtitle": "Sous-titre"],
                ]
            ]),
        ])

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", MetadataAction.self),
            config: ResolvedConfig(bundleID: "com.example.app", metadataDirectory: tempDirectory.path),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await MetadataAction().run(with: .init(push: true, directory: tempDirectory.path), context: context)

        #expect(result.operation == "push")
        #expect(result.localesProcessed == 1)
    }

    @Test("MetadataAction can submit pushed metadata for review")
    func pushSubmitsForReview() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let localeDirectory = tempDirectory.appendingPathComponent("en-US")
        try FileManager.default.createDirectory(at: localeDirectory, withIntermediateDirectories: true)
        try "Release Name".write(to: localeDirectory.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
        try "Ready to ship".write(to: localeDirectory.appendingPathComponent("description.txt"), atomically: true, encoding: .utf8)

        let client = makeClient(responses: [
            .json([
                "data": [
                    [
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "app-info-1"
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "info-loc-1",
                        "attributes": ["locale": "en-US", "name": "Old"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    "id": "info-loc-1",
                    "attributes": ["locale": "en-US", "name": "Release Name"],
                ]
            ]),
            .json(["data": []]),
            .json([
                "data": [
                    "id": "version-loc-1",
                    "attributes": ["locale": "en-US", "description": "Ready to ship"],
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"],
                    ]
                ]
            ]),
            .json([
                "data": [
                    "id": "version-1",
                    "attributes": ["versionString": "1.2.3"],
                ]
            ]),
            .json([
                "data": [
                    "id": "version-1",
                    "attributes": ["versionString": "1.2.3"],
                ]
            ]),
            .json([
                "data": [
                    "id": "review-1"
                ]
            ]),
        ])

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", MetadataAction.self),
            config: ResolvedConfig(
                bundleID: "com.example.app",
                metadataDirectory: tempDirectory.path,
                submitForReview: true,
                automaticRelease: false,
                phasedRelease: false
            ),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await MetadataAction().run(
            with: .init(push: true, directory: tempDirectory.path, submitForReview: true),
            context: context
        )

        #expect(result.operation == "push")
        #expect(result.localesProcessed == 1)
    }
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
#endif

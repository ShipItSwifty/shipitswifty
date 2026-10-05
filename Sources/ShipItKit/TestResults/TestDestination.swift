import Foundation

/// A string-backed enum with an `other` escape hatch.
///
/// Known values give built-in code exhaustive, type-safe switches. An unknown value is kept (not rejected) as
/// `other`, so a result from a plugin, or one exported by a newer ShipIt, still decodes and groups correctly
/// while built-in behavior simply treats it as unsupported.
public protocol OpenStringEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    init(rawValue: String)
}

extension OpenStringEnum {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The operating system or runtime a test executed on.
///
/// This is where the tests ran, not which tool ran them and not which framework built the project: a single
/// Kotlin Multiplatform build produces results for `jvm`, `android` and `ios` at once.
public enum TestPlatform: OpenStringEnum {
    case ios, android, macos, linux, windows, jvm, js, unknown
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ios": self = .ios
        case "android": self = .android
        case "macos": self = .macos
        case "linux": self = .linux
        case "windows": self = .windows
        case "jvm": self = .jvm
        case "js": self = .js
        case "unknown": self = .unknown
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ios: "ios"
        case .android: "android"
        case .macos: "macos"
        case .linux: "linux"
        case .windows: "windows"
        case .jvm: "jvm"
        case .js: "js"
        case .unknown: "unknown"
        case .other(let value): value
        }
    }

    /// The platform of the machine ShipIt is running on, for tests that execute on the host.
    public static var host: TestPlatform {
        #if os(macOS)
        return .macos
        #elseif os(Linux)
        return .linux
        #elseif os(Windows)
        return .windows
        #else
        return .unknown
        #endif
    }

    /// A name for people, as printed by the CLI.
    public var displayName: String {
        switch self {
        case .ios: "iOS"
        case .android: "Android"
        case .macos: "macOS"
        case .linux: "Linux"
        case .windows: "Windows"
        case .jvm: "JVM"
        case .js: "JavaScript"
        case .unknown: "Unknown"
        case .other(let value): value
        }
    }
}

/// The tool that executed the tests.
///
/// ShipIt's behavior depends on it: how a failed test is selected for a rerun, how infrastructure failures
/// are recognized, and which command is run. Parsing, by contrast, follows the artifact format, so one JUnit
/// reader serves `gradle` and `swift-test`.
public enum TestRunner: OpenStringEnum {
    case xcodebuild, gradle, swiftTest, flutterTest, jest
    /// A result assembled from several inputs that did not share one runner.
    case multiple
    case unknown
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "xcodebuild": self = .xcodebuild
        case "gradle": self = .gradle
        case "swift-test": self = .swiftTest
        case "flutter-test": self = .flutterTest
        case "jest": self = .jest
        case "multiple": self = .multiple
        case "unknown": self = .unknown
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .xcodebuild: "xcodebuild"
        case .gradle: "gradle"
        case .swiftTest: "swift-test"
        case .flutterTest: "flutter-test"
        case .jest: "jest"
        case .multiple: "multiple"
        case .unknown: "unknown"
        case .other(let value): value
        }
    }
}

/// What kind of environment a destination is.
public enum TestDestinationKind: String, Codable, Sendable, Hashable {
    case simulator, emulator, device
    /// The machine running the tests (JVM unit tests, `swift test`, Jest).
    case host
}

/// Where a set of tests ran: the unit a runner executes against, such as one Xcode destination running one
/// test plan, one Gradle test task, or the host machine.
///
/// Every test and suite under a destination shares its platform, so results list destinations once and tests
/// refer to them by ``id``. (Not an Xcode *target*, which is a module, or ``CoverageTarget``.)
public struct TestDestination: Codable, Sendable, Hashable {
    /// Stable within a run and across machines: built from what identifies the environment, never from
    /// absolute paths or process identifiers.
    public let id: String
    public let platform: TestPlatform
    public let kind: TestDestinationKind?
    /// The device, simulator or emulator name, when there is one.
    public let name: String?
    /// The unit the runner executed: a Gradle task, an Xcode test plan.
    public let scope: String?

    public init(platform: TestPlatform, kind: TestDestinationKind? = nil, name: String? = nil, scope: String? = nil) {
        self.platform = platform
        self.kind = kind
        self.name = name
        self.scope = scope
        id = [platform.rawValue, kind?.rawValue, name, scope].compactMap { $0 }.joined(separator: ":")
    }

    /// The machine ShipIt is running on.
    public static func host(scope: String? = nil) -> TestDestination {
        TestDestination(platform: .host, kind: .host, scope: scope)
    }
}

// MARK: - Deriving destinations from what each runner reports

extension TestDestination {
    /// The destination a Gradle test task runs against, from its name and, for connected tests, the device
    /// AGP reports.
    ///
    /// Kotlin Multiplatform names the target in the task (`iosSimulatorArm64Test`, `jvmTest`); Android local
    /// unit tests are `test<Variant>UnitTest` and run on the host JVM but belong to Android. An unrecognized
    /// task yields `unknown` rather than a guess.
    static func gradle(task: String, device: String? = nil) -> TestDestination {
        let name = task.split(separator: ":").last.map(String.init) ?? task
        if name.hasPrefix("connected") {
            let emulator = device.map { $0.localizedCaseInsensitiveContains("avd") || $0.localizedCaseInsensitiveContains("emulator") }
            return TestDestination(
                platform: .android, kind: device == nil ? nil : (emulator == true ? .emulator : .device), name: device, scope: name)
        }
        if name.range(of: #"^test.*UnitTest$"#, options: .regularExpression) != nil {
            return TestDestination(platform: .android, kind: .host, scope: name)
        }
        let lower = name.lowercased()
        if lower.hasPrefix("iossimulator") || lower == "iosx64test" {
            return TestDestination(platform: .ios, kind: .simulator, scope: name)
        }
        if lower.hasPrefix("ios") { return TestDestination(platform: .ios, kind: .device, scope: name) }
        if lower.hasPrefix("macos") { return TestDestination(platform: .macos, kind: .host, scope: name) }
        if lower.hasPrefix("linux") { return TestDestination(platform: .linux, kind: .host, scope: name) }
        if lower.hasPrefix("mingw") { return TestDestination(platform: .windows, kind: .host, scope: name) }
        if lower.hasPrefix("tvos") || lower.hasPrefix("watchos") {
            return TestDestination(platform: .other(lower.hasPrefix("tvos") ? "tvos" : "watchos"), kind: .simulator, scope: name)
        }
        if lower.hasPrefix("js") || lower.hasPrefix("wasm") { return TestDestination(platform: .js, kind: .host, scope: name) }
        if lower == "test" || lower == "jvmtest" || lower == "desktoptest" {
            return TestDestination(platform: .jvm, kind: .host, scope: name)
        }
        return TestDestination(platform: .unknown, scope: name)
    }

    /// The destination an `xcodebuild -destination` specifier names, such as
    /// `platform=iOS Simulator,name=iPhone 16,OS=18.2`.
    ///
    /// - Parameter resolvedName: The human device name from a result bundle. A specifier that identifies the
    ///   device only by UDID (`id=`) would otherwise name it by that UDID, which differs on every machine.
    static func xcode(specifier: String, plan: String? = nil, resolvedName: String? = nil) -> TestDestination {
        var fields: [String: String] = [:]
        for part in specifier.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { fields[pair[0].lowercased()] = pair[1] }
        }
        // `generic/platform=iOS Simulator` is the same specifier without a device.
        return xcode(
            platformName: fields["platform"] ?? fields["generic/platform"], name: fields["name"] ?? resolvedName ?? fields["id"],
            plan: plan)
    }

    /// The destination for an Xcode platform name (`iOS Simulator`, `macOS`, `tvOS`) as `xcodebuild` and
    /// `xcresulttool` spell it.
    static func xcode(platformName: String?, name: String?, plan: String? = nil) -> TestDestination {
        let platform = platformName?.lowercased() ?? ""
        let kind: TestDestinationKind = platform.contains("simulator") ? .simulator : (platform.hasPrefix("macos") ? .host : .device)
        let resolved: TestPlatform
        if platform.hasPrefix("ios") {
            resolved = .ios
        } else if platform.hasPrefix("macos") {
            resolved = .macos
        } else if platform.hasPrefix("tvos") {
            resolved = .other("tvos")
        } else if platform.hasPrefix("watchos") {
            resolved = .other("watchos")
        } else if platform.hasPrefix("visionos") || platform.hasPrefix("xros") {
            resolved = .other("visionos")
        } else {
            return TestDestination(platform: .unknown, name: name, scope: plan)
        }
        return TestDestination(platform: resolved, kind: kind, name: name, scope: plan)
    }
}

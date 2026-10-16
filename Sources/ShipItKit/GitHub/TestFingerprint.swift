import Crypto
import Foundation
import MobileTesting

/// A key for "the same test" that survives sharding, reordering and a different simulator.
///
/// `ParsedTestCase.stableID` correlates a test across attempts inside one run, so ShipIt prefixes it with the
/// plan's and destination's position (`plan-1:destination-2:`). That position changes when plans or shards are
/// reordered, which would file a new issue for a test that was already reported. The fingerprint is built from what
/// identifies the test instead: the runner, the plan it ran under, and the runner's own selector for it.
public enum TestFingerprint {
    /// The runner's name for the test, without any ShipIt bookkeeping.
    public static func identity(of test: ParsedTestCase) -> String {
        switch test.rerunSelector {
        case .xcodeOnlyTesting(let value), .gradleTestFilter(let value), .swiftTestFilter(let value):
            return value
        case .jest(let file, let fullName):
            return [file, fullName].compactMap { $0 }.joined(separator: "::")
        case .flutter(let name):
            return name
        case .unsupported, nil:
            return strippingPosition(from: test.stableID)
        }
    }

    /// 16 hex characters: short enough for an issue marker, long enough that a collision is not a practical concern.
    public static func make(for test: ParsedTestCase, runner: TestRunner) -> String {
        let plan = test.metadata?["plan"] ?? ""
        let key = [runner.rawValue, plan, identity(of: test)].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func strippingPosition(from stableID: String) -> String {
        stableID.replacingOccurrences(of: #"^(input-\d+:)?(plan-\d+:destination-\d+:)?"#, with: "", options: .regularExpression)
    }
}

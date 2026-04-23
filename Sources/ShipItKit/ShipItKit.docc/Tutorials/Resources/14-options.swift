import Foundation
import OSLog
import ShipItKit

public struct BuildTimingAction: Action {
    public static let name = "build-timing"
    public static let description = "Time how long a shell command takes and log the result."

    public struct Options: Codable, Sendable {
        /// The shell command to time (e.g. `"swift build"`).
        public var command: String
        /// Optional working directory; defaults to the project root.
        public var workingDirectory: String?

        public init(command: String, workingDirectory: String? = nil) {
            self.command = command
            self.workingDirectory = workingDirectory
        }
    }
}

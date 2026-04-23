extension BuildTimingAction {
    public struct Result: Codable, Sendable {
        public var command: String
        public var durationSeconds: Double
        public var exitCode: Int32

        public init(command: String, durationSeconds: Double, exitCode: Int32) {
            self.command = command
            self.durationSeconds = durationSeconds
            self.exitCode = exitCode
        }
    }
}

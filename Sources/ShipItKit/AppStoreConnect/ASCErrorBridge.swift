import AppStoreConnectKit

extension ShipItError {
    /// Translates an ``AppStoreConnectKit/ASCError`` from the external App Store
    /// Connect package into the matching ``ShipItError`` case so CLI exit-code
    /// mapping and error suggestions keep working unchanged.
    init(asc error: ASCError) {
        switch error {
        case .apiError(let statusCode, let body):
            self = .apiError(statusCode: statusCode, body: body)
        case .jwtGenerationFailed(let underlying):
            self = .jwtGenerationFailed(underlying: underlying)
        case .uploadFailed(let asset, let reason):
            self = .uploadFailed(asset: asset, reason: reason)
        case .invalidConfiguration(let reason):
            self = .invalidConfiguration(reason: reason)
        }
    }
}

/// Runs `body`, translating any ``AppStoreConnectKit/ASCError`` into the matching
/// ``ShipItError``. Wrap the App Store Connect–calling portion of an action so the
/// rest of ShipItKit and the CLI only ever see `ShipItError`.
func mappingASCErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as ASCError {
        throw ShipItError(asc: error)
    }
}

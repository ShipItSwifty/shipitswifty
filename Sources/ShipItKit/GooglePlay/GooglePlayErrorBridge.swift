import GoogleAuthKit

extension ShipItError {
    /// Translates a ``GoogleAuthKit/GoogleAPIError`` from the external Google Play package into
    /// the matching ``ShipItError`` case so CLI exit-code mapping and error suggestions keep
    /// working unchanged.
    ///
    /// Public because the CLI layer builds the Google Play client itself, in `CLIHelpers`, and
    /// needs to surface a bad service-account key as a `ShipItError` too.
    public init(google error: GoogleAPIError) {
        switch error {
        case .apiError(let statusCode, let body):
            self = .apiError(statusCode: statusCode, body: body)
        case .jwtGenerationFailed(let underlying):
            self = .jwtGenerationFailed(underlying: underlying)
        case .uploadFailed(let asset, let reason):
            self = .uploadFailed(asset: asset, reason: reason)
        case .invalidConfiguration(let reason):
            self = .invalidConfiguration(reason: reason)
        case .decodingFailed(let path, let type, let underlying):
            // ShipItError has no decoding case; an unexpected response shape is an API-side
            // problem, so it maps onto apiError with the detail preserved in the body.
            self = .apiError(
                statusCode: 0,
                body: "Could not decode \(type) from '\(path)': \(underlying.localizedDescription)"
            )
        }
    }
}

/// Runs `body`, translating any ``GoogleAuthKit/GoogleAPIError`` into the matching
/// ``ShipItError``. Wrap the Google-calling portion of an action so the rest of ShipItKit and the
/// CLI only ever see `ShipItError`.
func mappingGoogleErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as GoogleAPIError {
        throw ShipItError(google: error)
    }
}

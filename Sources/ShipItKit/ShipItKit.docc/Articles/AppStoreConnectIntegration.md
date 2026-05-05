# App Store Connect Integration

How ShipItKit talks to Apple — JWT auth, the typed REST client, uploads, and release management.

## Overview

ShipItKit ships with a complete, native Swift client for the App Store Connect API. There is **no `altool`, no `iTMSTransporter`, no Ruby gem** in the dependency graph. Authentication, retries, asset uploads, and release transitions all happen through ``AppStoreConnectClient`` — a single `actor` you can use directly or via the higher-level upload services.

## Credentials

Set these environment variables (or their Shipfile equivalents under `app_store_connect:`):

| Env var | Purpose |
|---|---|
| `ASC_KEY_ID` | API key identifier (10-char string) |
| `ASC_ISSUER_ID` | Issuer ID (UUID) |
| `ASC_PRIVATE_KEY` | Raw `.p8` file contents — **preferred for CI** |
| `ASC_PRIVATE_KEY_PATH` | Path to a `.p8` file — **preferred locally** |

`ASC_ISSUER_ID` is **not** stored inside the `.p8` file — it's shown on the App Store Connect API Keys page.

If you only use local Xcode actions (`build`, `test`, `archive`, `export`), you can skip ASC credentials entirely.

If you need help locating `team_id`, `ASC_KEY_ID`, or `ASC_ISSUER_ID`, see <doc:CredentialLookup>.

## Auth — JWT generation

``JWTGenerator`` is an `actor` that produces ES256-signed JWTs valid for 20 minutes (Apple's max). It caches the active token and rotates automatically before expiry. You usually never call it directly — ``AppStoreConnectClient`` handles it transparently.

```swift
let token = try await context.appStoreConnect.jwtGenerator.cachedOrNewToken()
```

## Direct API calls

```swift
let response = try await context.appStoreConnect.get(
    "/v1/apps",
    queryItems: [.init(name: "filter[bundleId]", value: "com.acme.MyApp")]
) as ASCListResponse<App>
```

The client is generic over response types. For 204 No Content endpoints, use ``NoContentResponse``:

```swift
try await context.appStoreConnect.delete(
    "/v1/betaTesters/\(testerId)"
) as NoContentResponse
```

## Upload services

Three layers from low to high:

1. ``AssetUploader`` — chunked multi-part upload of any asset to a reservation URL.
2. ``IPAUploadService`` — full IPA upload flow: create build → reserve → upload chunks → finalize → wait for processing.
3. ``UploadAction`` / ``TestFlightAction`` — the user-facing entrypoints used by the CLI and workflows.

```swift
// High-level
let result = try await UploadAction().run(
    with: .init(ipaPath: "./build/MyApp.ipa"),
    context: context
)
print("Build ID: \(result.buildID)")
```

## Rate limiting

``RateLimiter`` is wired into ``AppStoreConnectClient`` to keep ShipItKit polite under bulk operations. Apple's documented limits are conservative; the limiter sleeps and retries on `429 Too Many Requests` automatically using ``RetryPolicy`` with exponential backoff.

## Release management

``AppStoreReleaseService`` provides high-level transitions:

- Create or update an `AppStoreVersion`.
- Set release notes per locale.
- Toggle phased release / automatic release.
- Submit for App Review.

```bash
shipit upload --submit-for-review --phased-release
```

## Error mapping

ASC failures throw ``ShipItError/apiError(statusCode:body:)`` (HTTP 4xx/5xx) or ``ShipItError/uploadFailed(asset:reason:)`` (asset chunk failures). Both map to CLI exit code **30**. See <doc:ErrorHandling>.

## Testing

For unit tests, use the test support helper at `Tests/ShipItKitTests/TestSupport.swift`:

```swift
let client = makeClient(responses: [
    .json(["data": ["id": "abc-123"]], status: 200)
])
```

This wires `MockURLProtocol` into a real ``AppStoreConnectClient`` so your tests exercise the full request/response cycle without hitting Apple. See <doc:TestingWithMocks>.

## See also

- ``AppStoreConnectClient``
- ``JWTGenerator``
- ``IPAUploadService``
- ``AssetUploader``
- ``AppStoreReleaseService``
- ``RateLimiter``
- ``UploadAction``
- ``TestFlightAction``
- ``MetadataAction``
- <doc:CredentialLookup>
- <doc:CodeSigningAndVault>
- <doc:ErrorHandling>

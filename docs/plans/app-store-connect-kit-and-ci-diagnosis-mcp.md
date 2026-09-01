# Extract App Store Connect into a standalone package and build a CI-diagnosis MCP

## Status

This plan supersedes the draft at
`/Users/maniramezan/.claude/plans/lets-make-a-product-snappy-truffle.md`.

Do not begin scaffolding until the product decisions below are confirmed. Once confirmed,
execute the migration in the staged order described here so ShipItSwifty never depends on an
unpublished package version.

## Context

Xcode Cloud exposes build runs, actions, issues, test results, and artifacts through the App
Store Connect API. ShipItSwifty already contains a native App Store Connect client, but teams
that use Xcode Cloud may not use ShipItSwifty as their release runner. The reusable API client
and Xcode Cloud diagnosis surface therefore belong in a standalone package and executable.

## Product decisions to confirm

- Repository and package name. Proposed repository: `app-store-connect-kit`; package and
  primary library product: `AppStoreConnectKit`.
- Executable product name. Proposed: `asc-mcp` with target `ASCMCPServer`.
- Initial package version. Use a bare SemVer tag without a `v` prefix.
- AI provider and model for `asc_ci_diagnose`, including provider-specific environment variable
  names. The implementation must depend on a provider protocol, not a concrete provider in the
  tool handler.
- Minimum Apple platform. Proposed: macOS 15 for the upload product. Linux support is implicit
  in SwiftPM and is verified through a Linux build; there is no `.linux` platform declaration.
- Compatibility policy. This plan preserves existing `import ShipItKit` source compatibility
  for one deprecation cycle through a re-export. Removing that compatibility layer later is a
  separate breaking release.

## Agreed architecture

The new repository contains three products:

1. `AppStoreConnectKit`: a cross-platform library for credentials, JWT generation, rate
   limiting, the REST client, DTOs, asset upload over HTTP, release orchestration, and Xcode
   Cloud read APIs.
2. `AppStoreConnectUploadKit`: a macOS-only library for IPA upload through `xcrun altool` and
   IPA build-version extraction.
3. `asc-mcp`: a cross-platform stdio MCP executable for inspecting and diagnosing Xcode Cloud
   build failures.

ShipItSwifty then consumes the two library products and deletes its in-tree App Store Connect
implementation. There remains one implementation source of truth.

The entire product is implemented in Swift. The MCP uses the official Swift MCP SDK, the AI
provider clients are native Swift implementations, and artifact downloading, archive handling,
redaction, normalization, and diagnosis orchestration all run in-process in Swift. Do not add
Python, Node.js, Ruby, shell-script, or separately installed parser runtimes. A Swift package
dependency is acceptable only after its platform support, license, maintenance status, and
security behavior are reviewed and pinned.

During the compatibility cycle, ShipItKit uses:

```swift
@_exported import AppStoreConnectKit
#if os(macOS)
@_exported import AppStoreConnectUploadKit
#endif
```

This is intentional compatibility infrastructure. Existing consumers currently receive
`AppStoreConnectClient`, its public DTOs, and the two services from `import ShipItKit`; moving
the declarations to another Swift module without a re-export would be source-breaking. The
re-export and its eventual removal must be documented.

## New repository layout

```text
Package.swift
Package.resolved
Sources/
  AppStoreConnectKit/
    AppStoreConnectClient.swift
    ASCCredentials.swift
    ASCError.swift
    JWTGenerator.swift
    RateLimiter.swift
    RetryPolicy.swift
    AppStoreReleaseService.swift
    Upload/
      AssetUploader.swift
    Models/
      AppModels.swift
      UploadModels.swift
      CIModels.swift
    XcodeCloud/
      CIBuildAPI.swift
      ASCPaginator.swift
    Support/
      Logger+ForType.swift
  AppStoreConnectUploadKit/
    IPAUploadService.swift
    Altool.swift
    PlistBuildVersion.swift
  ASCMCPServer/
    main.swift
    Configuration/
    Providers/
      DiagnosisProvider.swift
    Security/
      DiagnosticRedactor.swift
      ArtifactDownloader.swift
    Tools/
Tests/
  AppStoreConnectKitTests/
  AppStoreConnectUploadKitTests/
  ASCMCPServerTests/
```

## Package manifest and cross-platform requirements

- Use Swift tools version 6.0 and strict Swift 6 language mode.
- Declare `platforms: [.macOS(.v15)]`; do not attempt to declare `.linux`.
- Add `swift-log`, `swift-crypto`, `jwt-kit`, and the MCP SDK as direct dependencies of the
  targets that import them.
- Use `Crypto`, not `CryptoKit`, in `AssetUploader` so MD5 computation builds on Linux.
- Files that use `URLSession`, `URLRequest`, or `URLProtocol` must conditionally import
  `FoundationNetworking` on Linux:

  ```swift
  import Foundation
  #if canImport(FoundationNetworking)
  import FoundationNetworking
  #endif
  ```

- Keep all `AppStoreConnectUploadKit` declarations under `#if os(macOS)`. ShipItSwifty adds
  that product dependency with `.when(platforms: [.macOS])`.
- Pin the reviewed MCP SDK compatibility range explicitly. The reviewed baseline is `0.12.1`;
  because the SDK is pre-1.0, use `.upToNextMinor(from: "0.12.1")`, commit
  `Package.resolved` for executable development and CI, and update only through an explicit
  dependency-update change.
- Implement the server with the official `modelcontextprotocol/swift-sdk` package. Do not add
  a second MCP framework or bridge to an MCP implementation in another language.
- The stdio MCP server must write JSON-RPC only to stdout. All diagnostics and logs go to
  stderr through a logger configured for stderr.

## Public API and typed seams

### Credentials

```swift
public struct ASCCredentials: Sendable {
    public let keyID: String
    public let issuerID: String
    public let privateKeyData: Data
}
```

`AppStoreConnectClient` gets a designated `init(credentials:serverURL:session:tokenProvider:)`.
For migration compatibility, retain the existing `init(keyID:issuerID:privateKeyData:...)` as
a forwarding initializer during the initial release.

ShipItKit adds a throwing adapter rather than an optional `flatMap` that can hide partial
configuration:

```swift
extension ActionContext {
    func requireASCCredentials() throws -> ASCCredentials
}
```

It must preserve the current user-facing messages for missing key ID, issuer ID, and private
key material.

### Errors

The standalone package owns `ASCError`:

```swift
public enum ASCError: Error, Sendable {
    case apiError(statusCode: Int, body: String)
    case invalidConfiguration(reason: String)
    case jwtGenerationFailed(reason: String)
    case uploadFailed(asset: String, reason: String)
}
```

Use a stable `String` reason rather than exposing dependency-specific underlying error values
across the package boundary. Preserve the original localized description when converting an
underlying JWT error into the reason.

ShipItKit defines one central async boundary helper that maps `ASCError` to the corresponding
`ShipItError` case and passes all other errors through unchanged. Wrap the complete execution
of every ASC-backed action (`upload`, `testflight`, `metadata`, `provision`, `dsym`, and signing
paths that call the certificate/profile managers), including direct client calls. Add tests
that assert the existing exit codes and `CLIHelpers.errorSuggestions` output.

### Release service

`AppStoreReleaseService.pullMetadata` takes only `bundleID` and `directory`; it does not take
credentials, shell context, or an action context.

`pushMetadata` and `submitForReview` receive a lazy, typed version provider:

```swift
public typealias VersionProvider = @Sendable () async throws -> String
```

The service calls the provider only when no App Store version exists and a new version must be
created. ShipItSwifty supplies a closure backed by `VersionBumper`. This preserves current
behavior and avoids resolving or mutating version state when an existing version is available.

### IPA upload service

`IPAUploadService` remains bound to an `AppStoreConnectClient` and receives concrete
`ASCCredentials`, `ShellContext`, and `Logger` values rather than `ActionContext`. Preserve its
config validation messages, polling behavior, cancellation propagation, file permissions, and
shell-error mapping.

Add a concurrency-safe key-staging helper with reference counting or serialization for
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`; two concurrent uploads must not remove a
key while another upload is using it.

## Xcode Cloud API

Implement typed wrappers for:

| Method | Endpoint |
|---|---|
| `ciProducts(appID:)` | `GET /v1/ciProducts?filter[app]=...` |
| `ciWorkflows(productID:)` | `GET /v1/ciProducts/{id}/workflows` |
| `ciBuildRuns(workflowID:pageLimit:)` | `GET /v1/ciWorkflows/{id}/buildRuns?sort=-number` |
| `ciBuildRun(id:)` | `GET /v1/ciBuildRuns/{id}` |
| `ciBuildActions(buildRunID:)` | `GET /v1/ciBuildRuns/{id}/actions` |
| `ciIssues(buildActionID:)` | `GET /v1/ciBuildActions/{id}/issues` |
| `ciTestResults(buildActionID:)` | `GET /v1/ciBuildActions/{id}/testResults` |
| `ciArtifacts(buildActionID:)` | `GET /v1/ciBuildActions/{id}/artifacts` |
| `ciArtifact(id:)` | `GET /v1/ciArtifacts/{id}` |

Requirements:

- Model Apple JSON:API relationships and `included` resources. Source branch/tag and pull
  request information are relationships, not plain build-run attributes. Request
  `include=sourceBranchOrTag,pullRequest` where supported or follow the relationship links.
- Model API string states as tolerant raw-value wrappers or enums with an unknown fallback so
  a newly introduced Apple value does not break decoding.
- Implement reusable pagination by following `links.next`. All list APIs return page objects;
  no tool may silently report the first page as the complete result.
- Respect Apple's documented maximum page size of 200.
- The workflow build-runs endpoint does not provide server-side branch or completion-status
  filters. `asc_ci_list_build_runs` must paginate in descending build-number order and apply
  typed branch/status filters locally. Its `limit` applies after filtering, not before.
- Tool arguments that accept workflow, product, or build identifiers must say whether they
  require opaque IDs. If human-readable names are supported, resolve them explicitly and
  return an ambiguity error when more than one resource matches.
- Add fixture tests for empty relationships, null attributes, unknown enum values, multiple
  pages, missing `links.next`, and malformed/error responses.

## MCP tools

- `asc_ci_list_products`
- `asc_ci_list_workflows`
- `asc_ci_list_build_runs`
  - Inputs: opaque workflow ID, optional branch, typed completion status, post-filter result
    limit.
- `asc_ci_get_build_run`
  - Input: build-run ID.
  - Output: normalized run, actions, issue counts, and failed tests.
- `asc_ci_get_issues`
  - Input: build-action ID.
  - Output: paginated normalized issues including file and line information when present.
- `asc_ci_get_artifacts`
  - Input: build-action ID.
  - Output: artifact IDs, names, types, and sizes. Do not emit signed download URLs by default.
    An explicit `includeDownloadUrls` flag may request freshly resolved short-lived URLs.
- `asc_ci_diagnose`
  - Input: build-run ID, optional `includeLogs` defaulting to `false`.
  - Output: `{ whatBroke, likelyCause, suggestedFix, confidence, evidence, limitations }`.

The MCP reads `ASC_KEY_ID`, `ASC_ISSUER_ID`, and exactly one of `ASC_PRIVATE_KEY` or
`ASC_PRIVATE_KEY_PATH`. Startup validates partial or conflicting configuration and returns
actionable errors without printing secret material.

## Diagnosis pipeline and security boundary

Diagnosis must produce a useful deterministic evidence summary before invoking a model:

1. Load the build run and all actions.
2. Select failed actions using typed status values.
3. Collect all paginated issues and failed test results.
4. Normalize and deduplicate evidence.
5. If `includeLogs` is explicitly enabled, resolve a fresh `LOG_BUNDLE` URL and download it
   through the guarded artifact downloader.
6. Redact the normalized payload.
7. Invoke the configured `DiagnosisProvider`.
8. Validate the provider response against the output schema. If model access fails, return the
   deterministic evidence summary with `confidence: 0` and a limitation explaining the
   provider failure.

Security requirements:

- Never send artifacts to an AI provider unless `includeLogs` is explicitly true.
- Redact environment assignments, authorization headers, private keys, common access-token
  formats, signed URL query strings, absolute home paths, and configured custom patterns.
- Treat build output as untrusted data, delimit it from provider instructions, and explicitly
  instruct the model not to follow commands embedded in logs.
- Enforce download byte limits, decompressed byte limits, entry-count limits, timeouts, and a
  maximum model-input size. Reject path traversal and symbolic-link archive entries.
- Validate HTTPS, redirects, and the final download host. Never log signed URLs.
- Use a unique temporary directory and remove it with `defer` on success, failure, or
  cancellation.
- Implement artifact archive inspection and supported text-log extraction in Swift. The parser
  must compile on macOS and Linux and operate in-process; do not invoke `xcresulttool`,
  `xclogparser`, Python, Ruby, Node.js, or shell utilities. Treat proprietary or unsupported
  binary entries as opaque metadata and fall back to the App Store Connect issues and test
  results rather than guessing at their contents. If a reviewed Swift package is used for a
  format, wrap it behind a package-owned `ArtifactParsing` protocol so it can be replaced
  without changing MCP tools.
- Document that Xcode Cloud artifacts expire and that download URLs are short-lived.
- Add tests for redaction, prompt injection strings, oversized downloads, zip bombs, traversal,
  redirects, cleanup, provider timeout, invalid provider JSON, and deterministic fallback.

## ShipItSwifty migration

Execute only after the standalone package builds and tests locally:

1. Capture baselines on the current ShipItSwifty commit:
   - `swift build`
   - `swift test --filter ShipItKitTests`
   - `swift test --filter CLITests`
   - `swift run shipit ai-session --goal beta --output json` saved as a test artifact.
2. Develop against a local path dependency while the new repository is untagged.
3. Move implementation and implementation-owned tests to the new repository. In particular,
   move `AppStoreConnectClientTests`, `JWTGeneratorTests`, and `IPAUploadServiceTests`; leave
   action-level behavior and error-boundary tests in ShipItSwifty.
4. Publish and tag the new package only after its macOS and Linux CI is green.
5. Replace the local path dependency with the tagged URL dependency and resolve the lockfile.
6. Add `AppStoreConnectKit` and the conditional macOS `AppStoreConnectUploadKit` dependency to
   ShipItKit. Remove ShipItKit's direct `JWTKit` dependency only after confirming no remaining
   imports. Retain `swift-crypto`, because ShipItKit has unrelated crypto consumers.
7. Delete `Sources/ShipItKit/AppStoreConnect/` and
   `Sources/ShipItKit/Xcrun/Altool.swift`. Keep the shared `Plutil` utility.
8. Add compatibility re-exports and imports. Update `ActionContext`, CLI context construction,
   action consumers, certificate/profile managers, test support, and DocC references.
9. Add `requireASCCredentials()`, the lazy version-provider adapter, and the central
   `ASCError`-to-`ShipItError` boundary.
10. Compare the post-migration `ai-session` JSON with the captured baseline. Normalize only
    documented nondeterministic fields, if any; otherwise require byte identity.

## Documentation updates

Update every ownership and usage reference, not only the checklist minimum:

- `AGENTS.md`
- `docs/architecture.md`
- `docs/features.md`
- `docs/plugin-development.md`
- `docs/testing.md`
- `Sources/ShipItKit/ShipItKit.docc/ShipItKit.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/AppStoreConnectIntegration.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/Architecture.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/CoreConcepts.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/TestingWithMocks.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/SwiftPMScripting.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/ActionsCatalog.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/CodeSigningAndVault.md`
- `Sources/ShipItKit/ShipItKit.docc/Articles/ErrorHandling.md`

State clearly that the implementation lives in the external package, ShipItKit temporarily
re-exports it for compatibility, and direct users should add `AppStoreConnectKit` explicitly.
No `ai-session` contract version, Shipfile schema, CLI command, or built-in action schema changes
are required.

## Verification

### New package

- macOS: `swift build` and `swift test`.
- Linux: build and test in the repository's pinned Linux container/toolchain. Do not rely on a
  bare macOS `--triple` invocation without a configured Linux SDK/sysroot.
- Confirm `AppStoreConnectKit` and `asc-mcp` compile and run on Linux.
- Confirm `AppStoreConnectUploadKitTests` run on macOS and no upload declarations leak onto
  Linux.
- Run fixture tests for client errors, JWTs, rate limiting, asset upload, all Xcode Cloud DTOs,
  relationships, pagination, filters, and unknown states.
- Run MCP protocol tests that assert stdout contains only valid JSON-RPC frames.
- Run MCP Inspector smoke tests for every tool.
- With dedicated least-privilege live credentials, test a deliberately broken Xcode Cloud
  build. Live tests must be opt-in and skipped when credentials are absent.
- Verify diagnosis with and without logs, with the provider unavailable, and after artifact
  expiry.

### ShipItSwifty

- `swift build`
- `swift test --filter ShipItKitTests`
- `swift test --filter CLITests`
- `make build-linux`
- `make test-linux`
- Verify `upload`, `testflight`, `metadata`, `provision`, `dsym`, and signing failures retain
  their existing `ShipItError`, exit code, human message, JSON error, and suggestions.
- Compile a small compatibility fixture that depends only on the `ShipItKit` product, imports
  only `ShipItKit`, constructs `AppStoreConnectClient`, and accesses
  `ActionContext.appStoreConnect`.
- Compare `ai-session` output against the captured pre-migration baseline.

## Completion criteria

The work is complete only when:

- The new package is tagged and independently consumable.
- macOS and Linux CI pass in the new repository.
- The MCP returns complete paginated evidence and has deterministic fallback behavior.
- Model-bound log transmission is explicit, bounded, redacted, and tested.
- ShipItSwifty contains no duplicate ASC implementation.
- Existing ShipItKit consumers remain source-compatible for the documented compatibility
  cycle.
- ShipItSwifty's existing ASC-backed behavior and exit codes are unchanged.
- All ownership, API, security, and migration documentation is current.

# ShipItSwifty — Architecture

> **DocC mirror:** Also available as the `Architecture` and `CoreConcepts` articles in the `ShipItKit` DocC archive.

ShipItSwifty is a pure-Swift CLI toolkit for automating iOS and Android app release workflows, built entirely in Swift 6.

| Principle | Detail |
|---|---|
| **Swift-native** | Swift 6, `async/await`, actors, `Sendable` throughout. No Ruby. |
| **Shell-powered** | `SwiftyShell` for type-safe, testable shell operations. |
| **CI-first** | Non-interactive by default, machine-readable JSON output, meaningful exit codes. |
| **Local-first** | Same commands on dev Mac and CI. Future server is a separate package on top of `ShipItKit`. |
| **Extensible** | Static-link plugin architecture — add custom actions without forking the core. |

---

## Layer diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User / CI Runner                            │
│   $ shipit archive --scheme MyApp --export-method app-store         │
└──────────────┬──────────────────────────────────────────────────────┘
               ▼
┌──────────────────────────┐
│        CLI (shipit)       │   Swift Argument Parser
│   Parses args, loads      │   Reads Shipfile.yml
│   config, orchestrates    │   Outputs JSON / human
└──────────┬───────────────┘
           ▼
┌──────────────────────────────────────────────────────────┐
│                      ShipItKit                            │
│  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌───────────┐  │
│  │ Builder  │ │ Signer   │ │ Uploader   │ │Snapshotter│  │
│  └────┬─────┘ └────┬─────┘ └─────┬──────┘ └─────┬─────┘  │
│  ┌────▼─────────────▼─────────────▼───────────────▼────┐  │
│  │              SwiftyShell                             │  │
│  │  Command · Pipeline · Git · XcodeBuild · Xcrun      │  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         AppStoreConnectClient                       │  │
│  │  JWT Auth · REST · Upload · TestFlight · Metadata   │  │
│  └──────────────────────┬──────────────────────────────┘  │
└─────────────────────────┼─────────────────────────────────┘
                          ▼
            ┌─────────────────────────────┐
            │  App Store Connect API      │
            │  api.appstoreconnect.apple  │
            │  .com/v1/...               │
            └─────────────────────────────┘
```

| Layer | Responsibility |
|---|---|
| **CLI (`shipit`)** | Argument parsing, config loading, human/JSON output, exit codes |
| **ShipItKit** | All business logic: build, sign, upload, screenshots, versioning, API calls |
| **SwiftyShell** | Type-safe shell execution, pipelines, `MockExecutor` for tests |
| **AppStoreConnectClient** | JWT generation, REST client for ASC API, upload protocol |

---

## Core execution model

```
Shipfile.yml / CLI flags / env vars
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient, platform)
        ↓
  ActionRegistry (actor) — maps action names → ActionDescriptors
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope (JSON-serializable)
```

---

## Package dependencies

```swift
// swift-tools-version: 6.0
// platforms: [.macOS(.v15)]
// swiftLanguageModes: [.v6]

dependencies: [
    .package(url: "https://github.com/maniramezan/swiftyshell", from: "0.1.0"),  // shell execution
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
    .package(url: "https://github.com/vapor/jwt-kit", from: "5.4.0"),       // ES256 JWT
    .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),          // YAML config
    .package(url: "https://github.com/apple/swift-crypto", from: "4.4.0"),  // code signing
    .package(url: "https://github.com/apple/swift-log", from: "1.6.3"),     // logging
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"), // DocC
]
```

**Products:**
- `.executable("shipit", targets: ["CLI"])`
- `.library("ShipItKit", targets: ["ShipItKit"])`
- `.library("XcodeBuildKit", targets: ["XcodeBuildKit"])` — standalone xcodebuild wrapper
- `.library("GradleKit", targets: ["GradleKit"])` — standalone Gradle/adb/bundletool wrapper
- `.library("XcodeGenKit", targets: ["XcodeGenKit"])` — standalone xcodegen wrapper

---

## Core type definitions

### `Action` protocol

```swift
public protocol Action: Sendable {
    associatedtype Options: Codable & Sendable
    associatedtype Result: Codable & Sendable

    static var name: String { get }
    static var description: String { get }

    func run(with options: Options, context: ActionContext) async throws -> Result
}
```

### `ActionDescriptor` (type-erased wrapper)

```swift
public struct ActionDescriptor: Sendable {
    public let name: String
    public let description: String
    public let runJSON: @Sendable (_ options: JSONValue?, _ context: ActionContext) async throws -> ActionResultEnvelope
}
```

### `ActionResultEnvelope`

```swift
public struct ActionResultEnvelope: Codable, Sendable {
    public let action: String
    public let status: String
    public let payload: JSONValue?
}
```

### `JSONValue`

Lossless JSON/YAML-compatible value type used for dynamically-typed action options:

```swift
@frozen
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

### `ActionRegistry`

```swift
public actor ActionRegistry {
    public func register(_ descriptor: ActionDescriptor) async throws   // throws .duplicateAction
    public func descriptor(named name: String) async -> ActionDescriptor?
    public func allDescriptors() async -> [ActionDescriptor]
}
```

### `ActionContext`

```swift
public struct ActionContext: Sendable {
    public let shell: ShellContext          // SwiftyShell context
    public let logger: ShipItLogger         // structured logger
    public let config: ResolvedConfig       // merged config
    public let appStoreConnect: AppStoreConnectClient
    public let googlePlay: GooglePlayClient?  // nil when no service account configured
    public let platform: Platform           // .ios (default) or .android
}
```

### `Workflow` and `WorkflowStep`

```swift
public struct WorkflowStep: Codable, Sendable {
    public let action: String       // registered action name
    public let options: JSONValue?  // forwarded to the action's Options
}

public struct Workflow: Sendable {
    public let name: String
    public let steps: [WorkflowStep]

    public init(_ name: String, steps: [WorkflowStep])
    public init(_ name: String, @WorkflowBuilder _ builder: () -> [WorkflowStep])
    public func run(context: ActionContext, registry: ActionRegistry) async throws -> WorkflowResult
}

@resultBuilder
public enum WorkflowBuilder {
    public static func buildBlock(_ steps: WorkflowStep...) -> [WorkflowStep]
    public static func buildArray(_ components: [[WorkflowStep]]) -> [WorkflowStep]
    public static func buildOptional(_ component: [WorkflowStep]?) -> [WorkflowStep]
    public static func buildEither(first: [WorkflowStep]) -> [WorkflowStep]
    public static func buildEither(second: [WorkflowStep]) -> [WorkflowStep]
}
```

### `ShipItError`

```swift
public enum ShipItError: Error, Sendable {
    // Build/Archive/Export — exit 10–12
    case buildFailed(exitCode: Int, log: String)
    case testFailed(exitCode: Int, failureCount: Int, log: String)
    case archiveFailed(exitCode: Int, log: String)

    // Code Signing — exit 20
    case signingResourceNotFound(description: String)
    case keychainError(underlying: Error)

    // API/Upload — exit 30
    case apiError(statusCode: Int, body: String)
    case jwtGenerationFailed(underlying: Error)
    case uploadFailed(asset: String, reason: String)

    // Screenshots — exit 40
    case screenshotCaptureFailed(device: String, locale: String, reason: String)

    // Metadata/Precheck — exit 50
    case precheckFailed(violations: [String])

    // Config/General — exit 2
    case invalidConfiguration(reason: String)
    case duplicateAction(name: String)
    case missingTool(name: String)
}
```

---

## CLI commands and exit codes

```
shipit <command> [global options]

COMMANDS:
  generate      Guided project setup — generates Shipfile.yml
                  --goal <local|beta|release>  Template to generate (default: beta)
                  --non-interactive            Use ProjectInspector + ShipfileSuggester; no prompts
                  --output json                Emit structured JSON on success
  schema        Print machine-readable Shipfile and workflow schema
                  --workflow <local|beta|release>  Emit only sections/actions relevant to that goal
  inspect       Inspect project facts for AI-assisted config generation
  suggest-config Generate a suggested Shipfile for local, beta, or release goals
  ai-bootstrap  Always-JSON bootstrap payload for AI agents (inspection + schema + suggestion + validation)
  ai-session    Stable, versioned JSON contract for AI agents (v1)
                  Returns: inferred config with confidence + provenance, secret descriptors,
                  ambiguity flags, readiness diagnosis, next action, agent prompt, next question
  validate      Validate Shipfile syntax, schema, and workflow semantics
  build         Compile the app (iOS: xcodebuild build, Android: gradlew assemble)
  test          Run tests (iOS: xcodebuild test, Android: gradlew test / connectedAndroidTest)
  archive       Archive the app (iOS: xcodebuild archive → .xcarchive, Android: gradlew bundle → .aab)
  lint          Static analysis (iOS: xcodebuild analyze, Android: gradlew lint)
  export        Export IPA from archive (iOS only)
  sign          Code signing subcommands: init | sync | import | cleanup (iOS only)
  upload        Upload IPA to App Store Connect (iOS only)
  testflight    Upload to TestFlight & distribute to groups (iOS only)
  play-store    Upload AAB to Google Play via service account (Android only)
  snapshot      Capture localized screenshots on simulators (iOS only)
  frame         Add device frames to screenshots (iOS only)
  version       Bump version / build number
  metadata      Pull / push App Store metadata
  precheck      Validate metadata before submission
  provision     Manage App IDs, devices, capabilities
  notify        Send build notifications
  validate      Validate Shipfile syntax, schema, and workflow semantics
    validate yml       Validate Shipfile YAML structure and workflow semantics
    validate metadata  Run precheck rules
    validate archive   Validate .xcarchive / .ipa bundle readiness (iOS only)
    validate bundle    Validate .aab / .apk bundle readiness via bundletool (Android only)
    validate all       Run all applicable stages
  run <workflow>    Execute a named workflow from Shipfile.yml
  coverage      Read and summarize native code coverage artifacts (iOS: xcresult, Android: JaCoCo)
  env           Print resolved config, env vars, and processed files
  doctor        Diagnose common setup issues for the selected Shipfile

GLOBAL OPTIONS:
  --shipfile <path>     Path to Shipfile.yml (default: ./Shipfile.yml, required for config-backed commands)
  --output <format>     human | json (default: human)
  --color <mode>        auto | always | never (default: auto, human output only)
  --no-color            Disable color in human output
  --verbose             Debug logging
  --ci                  CI mode: non-interactive, stricter error handling
  --dry-run             Preview without executing
  --platform <p>        ios | android (auto-detected from project files when omitted)
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments / config, including missing Shipfile.yml |
| `10` | Build failed |
| `11` | Test failed |
| `12` | Archive/export failed |
| `20` | Code signing error |
| `30` | Upload / API error |
| `40` | Screenshot capture failed |
| `50` | Precheck validation failed |

### JSON output format

```json
{
  "action": "build",
  "status": "success",
  "payload": {
    "appPath": "/path/to/MyApp.app",
    "dsymPath": "/path/to/MyApp.app.dSYM",
    "exitCode": 0,
    "warnings": 3
  }
}
```

### AI-friendly config workflow

`shipit ai-session` is the canonical machine-oriented entrypoint. It returns a single, stable JSON envelope with everything an agent needs.

```bash
# Canonical AI entrypoint — versioned, stable JSON contract
swift run shipit ai-session --goal beta

# Refresh after the user provides missing values
swift run shipit ai-session --goal beta --path /path/to/project

# Inspect raw project facts
swift run shipit inspect project --output json

# Goal-scoped schema slice (beta only)
swift run shipit schema --workflow beta --output json

# Generate a Shipfile
swift run shipit generate --goal beta

# Validate the generated Shipfile before execution
swift run shipit validate yml --shipfile ./Shipfile.yml --output json

# Validate App Store metadata before submission
swift run shipit validate metadata --output json

# Validate an xcarchive before upload
swift run shipit validate archive --archive-path ./build/MyApp.xcarchive

# Run all validation stages (yml + metadata + archive)
swift run shipit validate all --output json

# Non-interactive generation (agents/CI)
swift run shipit generate --goal beta --non-interactive

# Simulate a workflow without executing it (returns structured JSON)
swift run shipit run beta --dry-run --output json
```

#### `ai-session` JSON contract (v1)

```json
{
  "action": "ai-session",
  "status": "success | failure",
  "payload": {
    "version": "1",
    "goal": "local",
    "appConfig": [
      {
        "keyPath": "app.scheme",
        "value": "MyApp",
        "source": "detected | inferred | assumed | unresolved",
        "confidence": "high | medium | low | null",
        "why": "Scheme 'MyApp' matches the container name and is the only runnable scheme"
      },
      {
        "keyPath": "workflows.local[test].options.destinations",
        "value": null,
        "source": "unresolved",
        "confidence": null,
        "why": "Test destinations must be discovered via `xcodebuild -showdestinations` — ShipItSwifty never invents simulator names."
      }
    ],
    "missing": [
      { "keyPath": "workflows.local[test].options.destinations", "reason": "Destinations required for the test step.", "envVar": null }
    ],
    "ambiguities": [
      { "field": "app.scheme", "options": ["App", "AppExtension"], "message": "2 runnable schemes found." }
    ],
    "suggestedShipfile": "# Shipfile.yml ...",
    "readiness": {
      "goal": "local",
      "isReady": false,
      "blockers": [],
      "missingSecrets": [],
      "signingRisk": "low | medium | high",
      "unblockSteps": []
    },
    "nextAction": {
      "action": "resolve_blocker | resolve_ambiguity | create_shipfile | complete_config | run_workflow",
      "command": "shipit generate --goal local",
      "reason": "No Shipfile.yml exists. Generate a starter config..."
    },
    "agentPrompt": "You are helping an iOS developer automate their app release...",
    "nextQuestion": "This workflow includes a test step. Do you want to run tests? If yes, I can discover available simulators and devices for your scheme using `xcodebuild -showdestinations`."
  }
}
```

> **Note (beta goal):** When `goal` is `beta`, `appConfig` does not include the destinations entry, and `nextQuestion` asks about TestFlight upload intent instead.

Exit code `2` when `isReady: false`. Check this to gate further steps.

#### `run --dry-run --output json` contract

```json
{
  "action": "run",
  "status": "dry_run",
  "payload": {
    "workflow": "beta",
    "mode": "dry_run",
    "stepCount": 4,
    "steps": [
      { "index": 1, "action": "version", "options": { "bump": "build" } },
      { "index": 2, "action": "test", "options": { "retry_on_failure": true } },
      { "index": 3, "action": "archive", "options": null },
      { "index": 4, "action": "export", "options": null }
    ]
  }
}
```

---

## App Store Connect client

---

## `GooglePlayClient`

Native Google Play Developer API client, mirroring `AppStoreConnectClient`. Uses RS256 (RSA-SHA256) JWT auth from a service account JSON key.

```swift
public actor GooglePlayClient: Sendable {
    public init(serviceAccountJSON: Data) throws
    public func uploadBundle(at fileURL: URL, packageName: String, track: String, rolloutFraction: Double?) async throws -> String
}
```

### JWT authentication (RS256)

Service account JSON from Google Cloud Console. ShipIt extracts the `private_key` and signs with RS256 using the Security framework (no third-party JWT library).

| JWT field | Value |
|---|---|
| Algorithm | RS256 (RSA + SHA-256) |
| `iss` | Service account email |
| `scope` | `https://www.googleapis.com/auth/androidpublisher` |
| `aud` | `https://oauth2.googleapis.com/token` |
| `exp` | `iat` + 3600 s |

### Environment variables

| Variable | Description |
|---|---|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Full JSON content of the service account key |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Path to the service account key JSON file |

---

## `AppStoreConnectClient`

```swift
public actor AppStoreConnectClient: Sendable {
    public init(keyID: String, issuerID: String, privateKeyData: Data, serverURL: URL? = nil)

    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T
    public func post<B: Encodable & Sendable, R: Decodable & Sendable>(_ path: String, body: B) async throws -> R
    public func patch<B: Encodable & Sendable, R: Decodable & Sendable>(_ path: String, body: B) async throws -> R
    public func uploadAsset(at fileURL: URL, reservation: UploadReservation) async throws -> UploadCommit

    public var jwtGenerator: JWTGenerator { get }
    public var rateLimiter: RateLimiter { get }
}
```

### JWT authentication (ES256)

| JWT field | Value |
|---|---|
| Algorithm | ES256 (ECDSA with P-256 and SHA-256) |
| `kid` | Key ID from ASC → Users and Access → Integrations |
| `iss` | Issuer ID (team keys) |
| `exp` | ≤ 20 min for unscoped; up to 6 months for scoped GET-only |
| `aud` | `"appstoreconnect-v1"` |

```swift
public actor JWTGenerator {
    public static let defaultLifetime: Duration = .seconds(15 * 60)
    public func generateToken(scope: [String]? = nil, lifetime: Duration = .defaultLifetime) async throws -> String
    public func cachedOrNewToken() async throws -> String
}
```

### Asset upload protocol (multi-step)

1. **Reserve** — `POST` to create a resource record → returns upload operations
2. **Upload parts** — `PUT` each chunk to presigned S3 URLs
3. **Commit** — `PATCH` the resource with `uploaded: true` and MD5 checksum

Files are streamed in chunks — never fully loaded into memory (safe for 200 MB+ IPAs).

### Rate limiting

Apple returns `X-Rate-Limit: user-hour-lim:3500;user-hour-rem:2998` headers. `RateLimiter` parses these and pauses at 90% usage:

```swift
public actor RateLimiter: Sendable {
    public func throttleIfNeeded() async
    public func update(from headers: HTTPHeaders)
}
```

### ASC API resources used

| Resource Area | Key Endpoints | Feature |
|---|---|---|
| Apps | `GET /v1/apps` | List & identify apps |
| Builds | `GET /v1/builds` | Build listing, processing state |
| App Store Versions | `POST/PATCH /v1/appStoreVersions` | Create/manage versions |
| Version Localizations | `POST/PATCH /v1/appStoreVersionLocalizations` | Description, keywords, release notes |
| Screenshots | `POST /v1/appScreenshots` | Upload screenshots |
| Beta Groups | `GET/POST /v1/betaGroups` | TestFlight group management |
| Beta Build Localizations | `POST /v1/betaBuildLocalizations` | "What to Test" per locale |
| Review Submissions | `POST /v1/reviewSubmissions` | Submit for review |
| Certificates | `GET/POST /v1/certificates` | Create & download signing certs |
| Devices | `GET/POST /v1/devices` | Register devices |
| Bundle IDs | `GET/POST /v1/bundleIds` | Create/manage App IDs |
| Profiles | `GET/POST /v1/profiles` | Create provisioning profiles |

---

## Built-in actions

| Action | Platform | Description |
|---|---|---|
| `BuildAction` | iOS + Android | iOS: `xcodebuild build` → compiled products. Android: `./gradlew assemble<Variant>` → APK |
| `TestAction` | iOS + Android | iOS: `xcodebuild test` (multiple destinations, aggregate results). Android: `./gradlew test` (unit) or `./gradlew connectedAndroidTest` (instrumented) |
| `ArchiveAction` | iOS + Android | iOS: `xcodebuild archive` → `.xcarchive`. Android: `./gradlew bundle<Variant>` → `.aab` |
| `LintAction` | iOS + Android | iOS: `xcodebuild analyze`. Android: `./gradlew lint` |
| `ExportAction` | iOS only | `xcodebuild -exportArchive` → `.ipa` |
| `SignAction` | iOS only | Cert & profile sync via Git/S3 encrypted vault |
| `UploadAction` | iOS only | Upload IPA to ASC, optional review submission |
| `TestFlightAction` | iOS only | Upload to TestFlight, wait for processing, distribute |
| `PlayStoreAction` | Android only | Upload AAB to Google Play via service account |
| `ValidateBundleAction` | Android only | `bundletool validate --bundle` — pre-upload AAB/APK checks |
| `SnapshotAction` | iOS only | Simulator screenshot capture per locale/device |
| `FrameAction` | iOS only | Device frame overlay on screenshots |
| `VersionAction` | iOS + Android | Bump `CFBundleVersion` / `CFBundleShortVersionString` (iOS) or `versionCode`/`versionName` (Android) |
| `MetadataAction` | iOS only | Pull/push localized metadata; optional review submit |
| `PrecheckAction` | iOS only | Validate metadata before submission |
| `ProvisionAction` | iOS only | Create App IDs, register devices |
| `NotifyAction` | iOS + Android | Post to Slack or custom webhook |
| `GitAction` | iOS + Android | Git status, tagging, changelog |
| `DsymAction` | iOS only | Download/upload dSYM files |

---

## Introspection types

These types live in `Sources/ShipItKit/Introspection/` and power `ai-session`, `ai-bootstrap`, `suggest-config`, `inspect`, and `schema`.

| Type | Role |
|---|---|
| `ProjectInspector` | Discovers `.xcworkspace`/`.xcodeproj` (iOS) and Gradle files (`gradlew`, `build.gradle.kts`) (Android). Auto-detects platform. Runs `xcodebuild -list` + `-showBuildSettings` to extract schemes, bundle IDs, team IDs on iOS. |
| `ShipfileSuggester` | Generates goal-appropriate `Shipfile.yml` YAML from a `ProjectInspection` |
| `BuiltInSchemaCatalog` | Static catalog of `SchemaField`/`SchemaSection`/`ActionSchema` descriptors for every Shipfile key and action option — both iOS and Android |
| `SchemaValidator` | Validates a `JSONValue` tree against `SchemaField` rules |
| `ShipfileValidator` | Full YAML parse + schema + semantic workflow rule validation |
| `AISessionBuilder` | Builds a versioned `AISessionPayload` from a `ProjectInspection` + goal + platform. Android gets a Play Store-oriented agent prompt and Google Play secret descriptors. |
| `DestinationDiscovery` | Runs `xcodebuild -showdestinations` and parses the output into `[XcodebuildDestination]`; used by agents and `ai-session` to surface real simulator/device options instead of invented names |

### AI session model types (`AISessionTypes.swift`)

| Type | Description |
|---|---|
| `InferenceSource` | How a value was determined: `detected`, `inferred`, `assumed`, `unresolved` |
| `InferenceConfidence` | Confidence level: `high`, `medium`, `low` |
| `InferredConfigEntry` | A config value with `source`, `confidence`, and `why` |
| `SecretDescriptor` | A required secret with `envVar`, `acceptedFormats`, `exampleSource`, `preferFile` |
| `AmbiguityFlag` | A field with multiple candidates that requires user confirmation |
| `NextAction` | The single next step: `action` (stable key), `command` (exact CLI), `reason` |
| `AIReadiness` | Readiness summary: `isReady`, `blockers`, `missingSecrets`, `signingRisk`, `unblockSteps` |
| `AISessionPayload` | The full versioned contract returned by `shipit ai-session` |

---

## Future: service package

ShipItSwifty does not ship with a built-in server. If a hosted service becomes necessary (central credential management, webhooks, dashboards), it should be a separate package/repo built on top of `ShipItKit` — not part of this package.

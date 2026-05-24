# ``ShipItKit``

A Swift-native library for automating iOS and Android app release workflows.

## Overview

`ShipItKit` is the reusable core of ShipItSwifty — a Swift-native release toolkit for both Apple and Android platforms. It provides a composable action model, YAML-based workflow configuration, App Store Connect and Google Play API integration, code-signing utilities, and an AI-friendly schema for agent-driven setup.

All domain logic lives in `ShipItKit`. The `shipit` CLI is a thin argument-parsing layer on top of it, and any Swift app, server, or CI script can embed `ShipItKit` directly.

> **New here?** Start with <doc:GettingStarted>, then walk through the <doc:tutorials/Tutorials> for hands-on iOS, Android, and plugin chapters. For deep design background, see <doc:CoreConcepts> and <doc:Architecture>.

### Core execution model

```
Shipfile.yml / CLI flags / env vars / .env (auto-loaded)
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient, GooglePlayClient?, platform)
        ↓
  ActionRegistry (actor) — built-in + plugin actions, by name
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope (Codable)
```

> **Linux support:** Android actions, config resolution, and validation run natively on Linux. iOS-specific actions require macOS.

### Hard architectural rules

These constraints are enforced throughout the codebase:

1. All shell execution goes through **SwiftyShell** — never `Foundation.Process` directly.
2. All App Store Connect calls go through ``AppStoreConnectClient`` — no raw HTTP.
3. All public types are **`Sendable`** (Swift 6 strict concurrency).
4. Async work uses **structured concurrency** only.
5. Actions derive behaviour solely from their typed `Options` and the ``ActionContext`` — no hidden global state.

### Two ways to use it

| Surface | When to use |
|---|---|
| **`shipit` CLI** | Daily release work, CI pipelines, AI agents calling the binary directly. |
| **`ShipItKit` library** | Embedding release flows in your own Swift tools, custom servers, or test harnesses. Authoring plugins. |

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CredentialLookup>
- <doc:CoreConcepts>
- <doc:Architecture>
- <doc:tutorials/Tutorials>

### Configuration

- <doc:ConfigurationReference>
- <doc:SwiftPMScripting>
- <doc:Workflows>
- <doc:CompositeActions>
- <doc:Versioning>
- ``Shipfile``
- ``ResolvedConfig``
- ``ConfigResolver``
- ``Platform``

### Building, testing, distributing

- <doc:ActionsCatalog>
- <doc:Coverage>
- <doc:TestResults>
- <doc:Validation>
- <doc:OutputFormats>
- ``BuildAction``
- ``TestAction``
- ``ArchiveAction``
- ``ExportAction``
- ``UploadAction``
- ``TestFlightAction``
- ``MetadataAction``
- ``CoverageAction``
- ``LintAction``
- ``VersionAction``
- ``NotifyAction``

### iOS code signing & App Store Connect

- <doc:CodeSigningAndVault>
- <doc:AppStoreConnectIntegration>
- <doc:CredentialLookup>
- ``SignAction``
- ``ProvisionAction``
- ``AppStoreConnectClient``
- ``JWTGenerator``
- ``IPAUploadService``
- ``AssetUploader``
- ``AppStoreReleaseService``

### Android & Google Play

- <doc:AndroidAndGooglePlay>
- <doc:CredentialLookup>
- ``PlayStoreAction``
- ``GooglePlayClient``
- ``GooglePlayUploadService``
- ``GooglePlayJWTGenerator``
### Cross-platform build systems

- <doc:KMPIntegration>
- <doc:FlutterAndReactNative>
- ``BuildSystem``
- ``FlutterCLI``
- ``ReactNativeCLI``
- ``JSPackageManager``

### AI-assisted setup

- <doc:AISession>
- ``AISessionBuilder``
- ``AISessionPayload``
- ``ProjectInspector``
- ``ShipfileSuggester``
- ``ShipfileValidator``
- ``BuiltInSchemaCatalog``
- ``InferredConfigEntry``
- ``SecretDescriptor``

### Action model

- ``Action``
- ``ActionDescriptor``
- ``ActionValidationRule``
- ``ActionValidationContext``
- ``ActionContext``
- ``ActionResultEnvelope``
- ``CompositeAction``

### Workflow runtime

- ``ActionRegistry``
- ``Workflow``
- ``WorkflowStep``
- ``CustomActionConfig``

### Plugins

- <doc:WritingPlugins>
- ``ShipItPlugin``
- ``PluginRegistry``

### CI and automation

- <doc:CIIntegration>
- <doc:MigratingFromFastlane>

### Testing

- <doc:TestingWithMocks>
- <doc:TestResults>
- ``ActionContext/mock(executor:versioningSource:platform:)``

### Test result parsing

- ``ParsedTestRun``
- ``TestSummary``
- ``ParsedTestSuite``
- ``ParsedTestCase``
- ``TestCaseStatus``
- ``TestRerunSelector``
- ``ParsingDiagnostic``
- ``TestRunReport``
- ``TestAttempt``
- ``TestResultParser``
- ``TestArtifactLocator``
- ``TestRerunPlanner``

### Errors and reporting

- <doc:ErrorHandling>
- ``ShipItError``
- ``RetryPolicy``
- ``JSONValue``
- ``JSONReporter``
- ``Notifier``

### Lower-level wrappers

- ``Xcrun``
- ``Simctl``
- ``SimctlCommand``
- ``XcrunOption``

### Guided setup

- ``GenerateProjectAction``
- ``ProjectInspector``

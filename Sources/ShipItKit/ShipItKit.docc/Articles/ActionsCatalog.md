# Actions Catalog

Every built-in action that ships with ShipItKit, what it does, and the result it returns.

## Overview

Each action is a `Sendable` value type conforming to ``Action`` with typed `Options` and `Result`. They are registered in the shared ``ActionRegistry`` at process start and are callable both from `shipit` subcommands and from `Shipfile.yml` workflows.

The full configuration schema for any action is also returned by:

```bash
shipit schema --action build --output json
```

## Build & test

> **Cross-platform build systems:** When `ios.build_system:` / `android.build_system:` resolves to `kmp` (or, in future releases, `flutter` / `react_native`), ``BuildAction`` and ``TestAction`` run a build-system-specific compile step before the regular pipeline. Distribution actions further down this catalog are unchanged — they're artifact-path driven. See <doc:KMPIntegration>.

| Action | iOS | Android | KMP | Notes |
|---|:-:|:-:|:-:|---|
| ``BuildAction`` | ✅ | ✅ | ✅ | `xcodebuild build` / `gradlew assemble<Variant>`; KMP iOS links the shared framework via Gradle first |
| ``TestAction`` | ✅ | ✅ | ✅ | Multi-destination on iOS; unit + instrumented on Android; KMP iOS dispatches to `gradlew :shared:iosSimulatorArm64Test` |
| ``CoverageAction`` | ✅ | ✅ | ⚠️ | Reads `.xcresult` / JaCoCo XML. KMP support inherits per-target behaviour — see <doc:Coverage> |
| ``LintAction`` | ✅ | ✅ | ✅ | `xcodebuild analyze` / `gradlew lint` |

## Distribution prep

| Action | iOS | Android | Notes |
|---|:-:|:-:|---|
| ``ArchiveAction`` | ✅ | ✅ | Produces `.xcarchive` (iOS) or `.aab` / APK (Android) |
| ``ExportAction`` | ✅ | — | `xcodebuild -exportArchive` with auto-generated export options |
| ``SignAction`` | ✅ | — | Vault-style cert/profile sync |
| ``ProvisionAction`` | ✅ | — | Profile / App ID / device management via ASC |
| ``GenerateProjectAction`` | ✅ | — | Auto-runs XcodeGen / Tuist |

## Distribution upload

| Action | iOS | Android | Notes |
|---|:-:|:-:|---|
| ``UploadAction`` | ✅ | — | App Store upload via ``AppStoreConnectClient`` |
| ``TestFlightAction`` | ✅ | — | Build → tester groups → external distribution |
| ``MetadataAction`` | ✅ | — | Push/pull localized App Store metadata |
| ``PrecheckAction`` | ✅ | — | Validate metadata against Apple guidelines |
| ``ValidateArchiveAction`` | ✅ | — | Static validation of `.xcarchive` / `.ipa` |
| ``ValidateBundleAction`` | — | ✅ | Static validation of `.aab` / APK |
| ``PlayStoreAction`` | — | ✅ | Edit→upload→track→commit via Google Play API |

## Versioning & screenshots

| Action | iOS | Android | Notes |
|---|:-:|:-:|---|
| ``VersionAction`` | ✅ | ✅ | `agvtool` / project_spec / ASC sync — see <doc:Versioning> |
| ``SnapshotAction`` | ✅ | — | Capture via UI tests on a simulator matrix |
| ``FrameAction`` | ✅ | — | Frame screenshots with device chrome |

## Notifications & ops

| Action | iOS | Android | Notes |
|---|:-:|:-:|---|
| ``NotifyAction`` | ✅ | ✅ | Slack, Teams, Discord, webhook, macOS notifications |
| ``DsymAction`` | ✅ | — | Upload dSYMs to Firebase / custom destinations |

## Calling an action from Swift

Every action follows the same pattern:

```swift
let result = try await BuildAction().run(
    with: .init(scheme: "MyApp", configuration: .release),
    context: context
)
print("App at: \(result.appPath ?? "?")")
```

## Calling an action from a workflow

```yaml
workflows:
  release:
    - action: archive
      options: { export_method: app-store }
    - action: testflight
      options: { groups: ["Internal QA"] }
```

YAML keys are snake-case and decoded to camelCase Swift properties.

## Calling an action from the CLI

Every action also has a matching `shipit` subcommand. Run `shipit help <subcommand>` for the full option list:

```bash
shipit build --scheme MyApp
shipit testflight --changelog "Bug fixes."
shipit play-store --track internal
```

## Action result envelope

Every action returns an ``ActionResultEnvelope``:

```json
{
  "action": "build",
  "status": "success",
  "payload": {
    "appPath": "/Users/me/Library/Developer/Xcode/DerivedData/.../MyApp.app",
    "exitCode": 0,
    "warnings": 0
  }
}
```

See <doc:OutputFormats> for human vs. JSON rendering.

## See also

- <doc:Workflows>
- <doc:OutputFormats>
- <doc:ConfigurationReference>
- ``Action``
- ``ActionDescriptor``
- ``ActionRegistry``

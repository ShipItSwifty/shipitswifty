# ShipItSwifty — Feature Catalog

This document covers the planned feature surface, current v1 scope, the long-term roadmap, and a comparison with common release automation tools.

## v1 MVP scope

| Area | Included in v1.0 | Deferred |
|---|---|---|
| **CLI** | `init`, `schema`, `inspect project`, `suggest-config`, `validate`, `build`, `test`, `archive`, `export`, `sign sync`, `testflight`, `metadata`, `version`, `run`, `env`, `doctor` | Advanced git automation, PR creation, sales/finance reporting |
| **Code signing** | Vault-style sync from Git-backed encrypted storage | S3/GCS backends, certificate lifecycle beyond core sync |
| **Distribution** | TestFlight upload, metadata push/pull, App Store submission primitives | Full review automation coverage |
| **Screenshots** | Capture + upload basics | Framing, visual diffing, preview video processing |
| **Plugins** | Statically linked Swift package plugins at startup | Arbitrary runtime loading |

---

## Feature catalog

### AI-assisted configuration

| Feature | Description |
|---|---|
| **Schema export** | `shipit schema --output json` exposes the full Shipfile and workflow action contract for automation tools |
| **Project inspection** | `shipit inspect project --output json` discovers workspaces, projects, schemes, bundle IDs, team IDs, and related release files |
| **Config suggestion** | `shipit suggest-config --goal <local|beta|release>` produces a YAML draft plus missing-value hints |
| **Bootstrap response** | `shipit ai-bootstrap --goal <local|beta|release>` bundles inspection, schema, suggestion, and validation in one machine-readable response |
| **Validation** | `shipit validate` checks YAML parsing, top-level schema, workflow action options, and common semantic mistakes |

### Building

| Feature | Description |
|---|---|
| **Build** | `xcodebuild build` — configurable scheme, workspace/project, configuration, destination, build settings |
| **Archive** | `xcodebuild archive` → `.xcarchive` |
| **Export** | `xcodebuild -exportArchive` with export options plist generation |
| **Clean** | Clear derived data for reproducible builds |
| **SPM Build** | `swift build` for Swift Package Manager projects |
| **xcframework** | Build & package multi-platform xcframeworks |

### Testing

| Feature | Description |
|---|---|
| **Unit Tests** | `xcodebuild test` with parallel testing support |
| **UI Tests** | Run on specified simulators/devices |
| **Code Coverage** | Pass through xcodebuild coverage flags, expose result bundle paths |
| **Test Result Parsing** | Structured pass/fail/skip counts from `xcodebuild` output |

### Code signing

| Feature | Description |
|---|---|
| **Sync (vault-style)** | Encrypted certs & profiles in a Git repo (v1); S3/GCS backends planned |
| **Certificate Create** | Generate signing certificates via ASC API |
| **Profile Generate** | Create provisioning profiles via ASC API |
| **Device Register** | Register new UDIDs via ASC API |
| **Keychain Management** | Create/unlock temporary keychains on CI (`security` CLI) |
| **Notarize** | macOS app notarization via `xcrun notarytool` |

### Screenshots

| Feature | Description |
|---|---|
| **Capture** | Launch simulators per device/locale matrix, run UI test suite |
| **Organize** | Sort into `locale/device/` matching ASC upload format |
| **Frame** | Overlay device bezels; fallback copy if `frameit` unavailable |
| **Upload** | Batch upload to ASC per locale/display size |
| **Diff** | Visual diff against previously uploaded screenshots |

### App Store metadata

| Feature | Description |
|---|---|
| **Pull** | Download current metadata from ASC into local files (`metadata/en-US/description.txt`, etc.) |
| **Push** | Upload name, subtitle, description, keywords, `release_notes.txt` |
| **Precheck** | Validate text length, forbidden words, URL formats before upload |
| **Localization** | Upsert app-info and app-store-version localizations per locale |

### Versioning

| Feature | Description |
|---|---|
| **Bump Build** | Increment `CFBundleVersion` (sequential / timestamp / commit-count strategies) |
| **Bump Version** | Increment `CFBundleShortVersionString` (major/minor/patch) |
| **Git Tag** | Auto-tag releases with version |
| **Changelog** | Generate from git commits between tags |

### Distribution

| Feature | Description |
|---|---|
| **Upload to App Store** | IPA upload + optional review submission |
| **Upload to TestFlight** | Binary upload + distribution to existing groups |
| **Manage Beta Groups** | Existing group lookup and distribution |
| **Submit for Review** | Via `shipit upload` and `shipit metadata --push` |
| **Phased Release** | Primitive support when review submission is requested |

### Notifications

| Feature | Description |
|---|---|
| **Slack** | Slack webhook messages |
| **Custom Webhook** | POST JSON to any URL |
| **macOS Notification** | Local notification for interactive use |
| **Microsoft Teams / Discord** | Deferred |

### Source control

| Feature | Description |
|---|---|
| **Ensure Clean** | Fail if working tree is dirty |
| **Commit Version Bump** | Auto-commit after version increment |
| **Tag Release** | Create annotated git tag |
| **Push** | Push commits & tags to remote |
| **Changelog** | Generate from commits/PRs between refs |
| **Create PR** | Open pull request via GitHub API |

---

## Android roadmap (v2)

Android support is **not in v1 scope** but the architecture accommodates it.

| Area | iOS (v1) | Android (v2) |
|---|---|---|
| Build | `xcodebuild` | `gradle assembleRelease` |
| Test | `xcodebuild test` | `gradle test` / `connectedAndroidTest` |
| Sign | Certificates + profiles | Keystore + signing config |
| Upload | App Store Connect API | Google Play Developer API |
| Screenshots | `XCUITest` + simulators | Screengrab + emulators |
| Metadata | ASC metadata API | Play Console metadata API |
| Distribution | TestFlight | Internal App Sharing / Firebase |

### Platform architecture

`ActionContext` gains a `platform: Platform` field (default `.ios`). Actions read it to branch behavior.

```swift
public enum Platform: String, Codable, Sendable {
    case ios
    case android  // v2
}
```

Shipfile supports per-platform config blocks. `shipit run --platform android` merges the `android:` block on top of shared defaults:

```yaml
ios:
  scheme: MyApp
android:
  module: app
  build_type: release
```

`ShipItKit` will gain `GooglePlayClient` alongside `AppStoreConnectClient` in v2.

---

## Tool comparison

Migrating from `fastlane`? See the dedicated migration guide in [Walkthrough](walkthrough.md#migrating-from-fastlane).

| Common Tool | ShipItSwifty Equivalent | Notes |
|---|---|---|
| Archive / build | `shipit build` + `shipit archive` | Split into distinct steps |
| Test runner | `shipit test` | JSON structured output |
| Screenshot capture | `shipit snapshot` | SwiftyShell-driven simulator management |
| Screenshot framing | `shipit frame` | Device frame overlay |
| App Store upload | `shipit upload` + `shipit metadata` | Split metadata from binary upload |
| TestFlight upload | `shipit testflight` | Full TestFlight management |
| Code signing sync | `shipit sign sync` | Git/S3 encrypted cert vault |
| Certificate fetch | `shipit sign cert` | ASC API-driven |
| Profile fetch | `shipit sign profile` | ASC API-driven |
| App ID creation | `shipit provision` | App ID + capabilities |
| Metadata validation | `shipit precheck` | Pre-submission checks |
| Push certificates | `shipit sign push-cert` | Push notification certificates |
| Build number bump | `shipit version --bump build` | Multiple strategies |
| Version bump | `shipit version --bump minor` | SemVer support |
| Workflow file | `Shipfile.yml` workflows | YAML-based, Swift-native |
| App config | `Shipfile.yml` app section | Unified config |

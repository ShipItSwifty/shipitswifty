# ShipItSwifty — Feature Catalog

This document covers the planned feature surface, current v1 scope, the long-term roadmap, and a comparison with common release automation tools.

## v1 MVP scope

| Area | Included in v1.0 | Deferred |
|---|---|---|
| **CLI** | `init`, `schema`, `inspect project`, `suggest-config`, `ai-bootstrap`, `ai-session`, `validate`, `validate yml`, `validate metadata`, `validate archive`, `validate all`, `build`, `test`, `archive`, `export`, `sign sync`, `testflight`, `metadata`, `version`, `run`, `env`, `doctor` | Advanced git automation, PR creation, sales/finance reporting |
| **Code signing** | Vault-style sync from Git-backed encrypted storage | S3/GCS backends, certificate lifecycle beyond core sync |
| **Distribution** | TestFlight upload, metadata push/pull, App Store submission primitives | Full review automation coverage |
| **Screenshots** | Capture + upload basics | Framing, visual diffing, preview video processing |
| **Plugins** | Statically linked Swift package plugins at startup | Arbitrary runtime loading |

---

## Feature catalog

### AI-assisted configuration

| Feature | Description |
|---|---|
| **Schema export** | `shipit schema --output json` exposes the full Shipfile and workflow action contract. Use `--workflow <local\|beta\|release>` for a goal-scoped subset |
| **Project inspection** | `shipit inspect project --output json` discovers workspaces, projects, schemes, bundle IDs, team IDs, and related release files |
| **Config suggestion** | `shipit suggest-config --goal <local\|beta\|release>` produces a YAML draft plus missing-value hints |
| **Bootstrap response** | `shipit ai-bootstrap --goal <local\|beta\|release>` always returns JSON with inspection, schema, suggestion, and validation for AI agents |
| **AI session** | `shipit ai-session --goal <local\|beta\|release>` returns a **versioned, stable JSON contract** (v1) containing inferred config with confidence + provenance, secret descriptors, ambiguity flags, readiness diagnosis, next deterministic action, agent system prompt, and the single best follow-up question to ask the user |
| **Validation** | `shipit validate` (default: yml) checks YAML parsing, top-level schema, workflow action options, and common semantic mistakes. `shipit validate metadata` runs precheck rules. `shipit validate archive` validates xcarchive / ipa bundle readiness for upload. `shipit validate all` runs all stages. |

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

| Feature | Status | Description |
|---|---|---|
| **Unit Tests** | Implemented | `xcodebuild test` with scheme, one or more destinations, and configuration |
| **UI Tests** | Implemented | `--only-testing` / `--skip-testing` target filtering; run on any simulator or device destination |
| **Multi-destination runs** | Implemented | `destinations` array — each entry triggers a separate `xcodebuild test` pass; pass/fail/skip counts are aggregated across all destinations. Supports simulators, physical devices, and mixed matrices in one step. |
| **Destination discovery** | Implemented | `DestinationDiscovery` calls `xcodebuild -showdestinations` for the selected scheme and returns typed `XcodebuildDestination` values sorted simulators-first. Used by `ai-session` and `suggest-config` to avoid inventing simulator names. |
| **No-destination guard** | Implemented | When `destinations` (and the legacy `destination`) are both absent the action throws `ShipItError.invalidConfiguration` with an actionable message rather than guessing a name that may not be installed. |
| **Code Coverage** | Implemented | `-enableCodeCoverage YES`; auto-derives `./build/<scheme>-tests.xcresult` when coverage enabled and no explicit path given; any existing bundle at the resolved path is removed before xcodebuild runs, making repeated local and CI runs safe without manual cleanup |
| **Test Result Parsing** | Implemented | Structured pass/fail/skip counts from xcodebuild summary line; per-test `FAILED` line fallback for parallelized output |
| **Test Plans** | Implemented | `--test-plan` selects a named `.xctestplan` |
| **Retry on Failure** | Implemented | `retry_on_failure: true` passes `-retry-tests-on-failure` to xcodebuild |

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
| **Precheck** | Validate text length, forbidden words, URL formats before upload — also available as `shipit validate metadata` |
| **Archive readiness** | `shipit validate archive` — pre-upload checks: icon alpha, Info.plist completeness, bundle ID format, version keys, iPad orientation, and archive structure |
| **Localization** | Upsert app-info and app-store-version localizations per locale |

### Versioning

ShipItSwifty follows Apple's two-version model:

| Plist key | Format | Role |
|---|---|---|
| `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH` | User-facing marketing version. Changed only on explicit `bump: major/minor/patch`. |
| `CFBundleVersion` | plain integer | Internal build counter. Incremented on every beta run via `bump: build`. |

| Feature | Description |
|---|---|
| **Bump Build** | Increment `CFBundleVersion` only (`bump: build`). `CFBundleShortVersionString` is left untouched. Supports `sequential` (integer +1) and `timestamp` (`YYYYMMDDHHmm`) strategies. |
| **Bump Version** | Increment a segment of `CFBundleShortVersionString` (`bump: major/minor/patch`). Resets `CFBundleVersion` to `1`. |
| **Version Source — xcodeproj** | Reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` directly from Xcode build settings via `xcodebuild -showBuildSettings`. Writes via `agvtool new-marketing-version` / `agvtool new-version -all`. Falls back to agvtool read and then `plutil` on Info.plist for legacy projects without those build settings. |
| **Version Source — asc** | Reads the current build number from App Store Connect. Falls through to agvtool / plutil for the read phase. |
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
| Metadata validation | `shipit validate metadata` | Also available as `shipit precheck` (backwards-compat alias) |
| Archive validation | `shipit validate archive` | Pre-upload bundle readiness checks |
| Push certificates | `shipit sign push-cert` | Push notification certificates |
| Build number bump | `shipit version --bump build` | Multiple strategies |
| Version bump | `shipit version --bump minor` | SemVer support |
| Workflow file | `Shipfile.yml` workflows | YAML-based, Swift-native |
| App config | `Shipfile.yml` app section | Unified config |

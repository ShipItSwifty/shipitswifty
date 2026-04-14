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

### Workflow composition

| Feature | Description |
|---|---|
| **Custom actions** | Under `custom_actions:` in `Shipfile.yml`, define reusable parameterized step sequences and invoke them from workflows the same way as built-in actions. Supports declared parameters (with `type`, `required`, `default`), `{{param.NAME}}` substitution in step options (CI-safe — does not collide with `${ENV_VAR}`, GitHub Actions `${{ }}`, or CircleCI `<< >>`), nested composites with cycle detection, and collision detection against built-in action names. `shipit validate yml` enforces all of these rules. `shipit ai-session` surfaces declared composites to agents so they reuse instead of duplicate. |

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
| **No-destination guard** | Implemented | When `destinations` (and the legacy `destination`) are both absent, the action auto-discovers a suitable iPhone simulator using `DestinationDiscovery`. If no iPhone simulator is available, it throws `ShipItError.invalidConfiguration` with an actionable message listing what was found. |
| **Automatic destination discovery** | Implemented | When no destinations are configured, the test action auto-discovers available iPhone simulators via `xcodebuild -showdestinations`, preferring the highest OS version and Pro models. Eliminates manual simulator configuration for most projects. |
| **Code Coverage** | Implemented | `-enableCodeCoverage YES`; auto-derives `./build/<scheme>-tests.xcresult` when coverage enabled and no explicit path given; any existing bundle at the resolved path is removed before xcodebuild runs, making repeated local and CI runs safe without manual cleanup |
| **Test Result Parsing** | Implemented | Structured pass/fail/skip counts from xcodebuild summary line; per-test `FAILED` line fallback for parallelized output |
| **Test Plans** | Implemented | `--test-plan` selects a named `.xctestplan` |
| **Retry on Failure** | Implemented | `retry_on_failure: true` passes `-retry-tests-on-failure` to xcodebuild |

### Coverage Reporting

`shipit coverage` wraps and normalises native coverage artifacts — it does **not** generate coverage data itself.

| Feature | Status | Description |
|---|---|---|
| **iOS coverage summary** | Implemented | Reads `.xcresult` bundles via `xcrun xccov view --report --json`. Auto-discovers `./build/<scheme>-tests.xcresult` from config or globs `./build/`. |
| **Android coverage summary** | Implemented | Parses JaCoCo XML reports generated by `./gradlew jacocoTestReport`. Auto-discovers common Gradle output paths; supports explicit `--report <path>` override. |
| **First-party filtering** | Implemented | `--first-party-only` suppresses test bundles (`.xctest`), Swift package dependencies, and known vendor prefixes (Google, Firebase, etc.) by default. |
| **Target / module breakdown** | Implemented | `--targets` shows per-target (iOS) or per-module (Android) coverage. Aggregates JaCoCo packages into logical modules using the org-prefix convention. |
| **File breakdown** | Implemented | `--files` shows per-file coverage within each target/module. |
| **Include / exclude filters** | Implemented | `--include-target` / `--exclude-target` for surgical control. Include list overrides the first-party filter. |
| **Sorting and limiting** | Implemented | `--sort coverage` (default, lowest first — most actionable) or `--sort name`. `--limit <n>` caps output length. |
| **Output formats** | Implemented | `--format text` (human-readable with bar charts), `--format json` (stable, machine-readable), `--format markdown` (PR comments / CI summaries). |
| **Dry-run support** | Implemented | `--dry-run` prints what would be read without invoking `xccov` or reading the report. |
| **Workflow integration** | Implemented | `coverage` is a first-class workflow action; can follow a `test` step in `Shipfile.yml`. |

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
| **Version Source — project_spec** | Reads and writes version values directly in a YAML project spec file (e.g. XcodeGen `project.yml`). Performs line-by-line replacement to preserve formatting, comments, and structure. Configurable via `versioning.spec_path`, `versioning.build_key`, `versioning.marketing_key`. Falls back to `project_generation.spec_path` when `versioning.spec_path` is not set. |
| **Version Target Override** | The `version` action accepts a `target` option (`source_of_truth`, `project_spec`, or `xcodeproj`) to override the configured versioning source per-step, enabling workflows that write to the spec file even when the default source is `xcodeproj`. |
| **Git Tag** | Auto-tag releases with version |
| **Changelog** | Generate from git commits between tags |

### Project Generation

For iOS projects that use spec-driven project tools (XcodeGen, Tuist, etc.), ShipItSwifty can auto-generate the `.xcodeproj` before any Xcode-dependent workflow step.

| Feature | Status | Description |
|---|---|---|
| **Auto-generation** | Implemented | When `project_generation.tool` is configured in Shipfile.yml, `Workflow.run()` automatically generates the Xcode project before the first Xcode-dependent step (build, test, archive, etc.). Skips generation when the output project already exists. |
| **`generate_project` action** | Implemented | Explicit action for project generation. Supports `command`, `spec_path`, `output_project`, and `force` options. Registered as a first-class action in the action registry. |
| **XcodeGen support** | Implemented | Default command for `tool: xcodegen` is `xcodegen generate`. Custom commands are supported for non-standard invocations. |
| **Auto-generate toggle** | Implemented | `project_generation.auto_generate: false` disables auto-generation; the `generate_project` action must be invoked explicitly. |
| **Spec validation** | Implemented | Generation validates that the spec file exists before running and that the output project was created after the command completes. |

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

## Android support (v1)

Android support ships in v1 alongside iOS. Platform is auto-detected from project files (`gradlew` → Android, `*.xcworkspace`/`*.xcodeproj` → iOS) or set explicitly with `--platform android`.

### Android actions

| Action | CLI | Description |
|---|---|---|
| **Build** | `shipit build --platform android` | `./gradlew assembleRelease` (or configured variant) |
| **Archive** | `shipit archive --platform android` | `./gradlew bundleRelease` — produces an `.aab` |
| **Test** | `shipit test --platform android` | `./gradlew test` (unit) or `./gradlew connectedAndroidTest` (instrumented) |
| **Lint** | `shipit lint --platform android` | `./gradlew lint` |
| **Play Store** | `shipit play-store` | Upload AAB to Google Play via service account JWT auth |
| **Validate Bundle** | `shipit validate bundle` | `bundletool validate --bundle` — AAB/APK pre-upload checks |

### Android Shipfile example

```yaml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp
  play_track: internal
  keystore_path: ./certs/release.keystore
  keystore_password: ${ANDROID_KEYSTORE_PASSWORD}
  key_alias: release
  key_password: ${ANDROID_KEY_PASSWORD}

workflows:
  beta:
    steps:
      - action: test
      - action: archive
      - action: play_store
```

### Platform-aware commands

All commands accept `--platform ios|android`. When omitted, the platform is auto-detected:
- `gradlew` or `build.gradle.kts` in the root → `.android`
- `*.xcworkspace` or `*.xcodeproj` in the root → `.ios`
- Default → `.ios`

AI session is also platform-aware: `shipit ai-session --goal beta --platform android` returns an Android-specific agent prompt and secret descriptors for Google Play service accounts.

---

## Android roadmap (v2+)

| Area | Status |
|---|---|
| Build (Gradle assemble) | **Implemented** |
| Archive (Gradle bundle → AAB) | **Implemented** |
| Test (unit + instrumented) | **Implemented** |
| Lint | **Implemented** |
| Play Store upload | **Implemented** |
| Bundle validation (bundletool) | **Implemented** |
| Screenshots (Screengrab + emulators) | Deferred |
| Play Console metadata API | Deferred |
| Firebase App Distribution | Deferred |

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

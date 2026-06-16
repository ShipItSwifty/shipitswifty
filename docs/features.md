# ShipItSwifty — Feature Catalog

> **DocC mirror:** A condensed catalog with cross-links to action symbols lives in the `ActionsCatalog` article in the `ShipItKit` DocC archive. This file remains the authoritative roadmap.

This document covers the planned feature surface, current v1 scope, the long-term roadmap, and a comparison with common release automation tools.

## v1 MVP scope

| Area | Included in v1.0 | Deferred |
|---|---|---|
| **CLI** | `generate`, `schema`, `inspect project`, `suggest-config`, `ai-session`, `validate`, `validate yml`, `validate metadata`, `validate archive`, `validate all`, `build`, `test`, `archive`, `export`, `sign sync`, `testflight`, `metadata`, `version`, `run`, `env`, `doctor` | Advanced git automation, PR creation, sales/finance reporting |
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
| **Guided Shipfile generation** | `shipit generate --goal <local\|beta\|release>` inspects iOS/Android project files, confirms inferred values, writes `Shipfile.yml`, and offers to run `doctor`. It asks whether generated test steps should enable infrastructure retries for transient simulator/emulator/tool failures. For `--goal release`, the generated workflow includes a commit/tag/push tail (`v{{version}}`, gated by `when: "{{version_changed}}"`); generate offers to drive the bump from CI via `${RELEASE_BUMP}` and prints the CI prerequisites (full-history checkout, write permission, git identity). For Android signing, guides keystore discovery (detects existing env vars or `.env` values), prompts for missing credentials, and offers three persistence options: `.env` file (recommended for local dev), shell profile (~/.zshrc), or manual export. When writing `.env`, uses `${VAR_NAME}` references for values already set in the environment — only inlines literals for user-provided values. |
| **Config suggestion** | `shipit suggest-config --goal <local\|beta\|release>` produces a YAML draft plus missing-value hints without writing it |
| **AI session** | `shipit ai-session --goal <local\|beta\|release>` returns a **versioned, stable JSON contract** (v1) containing inferred config with confidence + provenance, secret descriptors, ambiguity flags, readiness diagnosis, next deterministic action, agent system prompt, and the single best follow-up question to ask the user. The prompt instructs agents to ask about `infrastructure_retry` whenever they generate or edit workflows with test steps. |
| **Validation** | `shipit validate` (default: yml) checks YAML parsing, top-level schema, workflow action options, and common semantic mistakes. `shipit validate metadata` runs precheck rules. `shipit validate archive` validates xcarchive / ipa bundle readiness for upload. `shipit validate bundle` validates Android AAB/APK bundles via `bundletool validate`; when no explicit `aab_path` / `apk_path` is provided it auto-discovers conventional native Gradle, Flutter, and React Native outputs. `shipit validate all` runs all stages. |

### Environment and credential management

| Feature | Description |
|---|---|
| **`.env` auto-loading** | ShipIt automatically loads `KEY=VALUE` pairs from a `.env` file in the Shipfile's directory before running any action. Existing process environment variables take precedence (are never overwritten). |
| **Smart `.env` generation** | When `shipit generate` writes a `.env` file and a value is already set in the process environment, it writes a `${VAR_NAME}` reference instead of inlining the literal — keeping the file portable and secret-free. |
| **Shell profile export** | `shipit generate` can alternatively append `export` lines to `~/.zshrc` or `~/.bashrc`. Detects which profile exists, avoids duplicates, and offers overwrite if signing vars already present. |
| **Config resolution priority** | CLI flags > `SHIPIT_*` env vars > `.env` file > `Shipfile.yml` > built-in defaults. Shipfile supports `${ENV_VAR}` expansion. |

### Linux and Docker support

| Feature | Description |
|---|---|
| **Linux builds** | Android actions (build, test, archive, lint, play-store, validate bundle) run natively on Linux. iOS-specific actions are gated behind `#if os(macOS)`. |
| **Docker workflow** | `make build-linux` / `make test-linux` / `make shell-linux` — uses direct volume mount for fast iteration. `make docker-build` / `make docker-test` builds a local image with SPM dependency caching. |
| **CI parity** | Same `swift build && swift test` on both macOS and Linux. Tests auto-skip macOS-only targets on Linux. |

### Workflow composition

| Feature | Description |
|---|---|
| **Custom actions** | Under `custom_actions:` in `Shipfile.yml`, define reusable parameterized step sequences and invoke them from workflows the same way as built-in actions. Supports declared parameters (with `type`, `required`, `default`), `{{param.NAME}}` substitution in step options (CI-safe — does not collide with `${ENV_VAR}`, GitHub Actions `${{ }}`, or CircleCI `<< >>`), nested composites with cycle detection, and collision detection against built-in action names. `shipit validate yml` enforces all of these rules. `shipit ai-session` surfaces declared composites to agents so they reuse instead of duplicate. |
| **Workflow tokens** | Top-level workflow steps can reference reserved tokens in their `options` and `when` values: `{{version}}` and `{{build_number}}` resolve from a prior `version` step (or the current versioning source), and `{{version_changed}}` is `true`/`false`. This lets a release tag the version it just bumped (`git` `tag_name: "v{{version}}"`) in a single `shipit run` — no external `jq`/env glue. Distinct from `{{param.NAME}}`; resolved at run time for top-level steps. |
| **Conditional steps** | Any workflow step may carry `when: "<expr>"`. Reserved tokens are substituted, then the result is evaluated for truthiness (`true`/`1`/`yes`); when falsy the step is skipped (status `skipped`) and the workflow continues. Used by the generated `release` scaffold to gate the `git` tag step with `when: "{{version_changed}}"` so build-only bumps don't re-tag. |
| **Release scaffold** | `shipit generate --goal release` emits a ready-to-edit `release` workflow for iOS and Android that bumps the marketing version (`bump: patch`, overridable via `${RELEASE_BUMP}`), builds/tests, distributes, then commits and tags `v{{version}}` (conditionally) and pushes. |

### Building

| Feature | Description |
|---|---|
| **Build** | `xcodebuild build` — configurable scheme, workspace/project, configuration, destination, build settings. xcodebuild output streams live to the console, and a summary (`** … SUCCEEDED **` plus warning/error counts) is printed even without `--verbose`. |
| **Archive** | `xcodebuild archive` → `.xcarchive`. Output streams live and a summary is printed even without `--verbose`. |
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
| **Test Result Parsing** | Implemented | Structured pass/fail/skip counts from xcodebuild/Gradle output. When available, ShipIt also captures named passed/failed tests from tool output or JUnit XML reports so workflow summaries can list concrete test names instead of only counts. |
| **Structured test artifact parsing** | Implemented | `shipit test-results` and `TestResultsAction` parse native `.xcresult` and Gradle JUnit XML artifacts into `ParsedTestRun` and `TestRunReport`, with optional JSON report export for CI artifacts. |
| **Test Plans** | Implemented | `--test-plan` selects a named `.xctestplan` |
| **Retry on Failure** | Implemented | `retry_on_failure: true` passes `-retry-tests-on-failure` to xcodebuild |
| **Selective failed-test reruns** | Implemented | `rerun_failed_tests: { enabled: true, max_attempts: 2 }` reruns only the failing iOS tests and Android JVM tests once, then reports flaky vs persistent failures in `TestRunReport`. |

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
| **Manual signing assets** | Install local or base64-provided `.p12` certificates and `.mobileprovision` profiles with path-first CI fallback |
| **Automatic signing in CI** | `build`/`archive`/`export` pass `-allowProvisioningUpdates` plus ASC API key flags (`-authenticationKeyID/IssuerID/Path`) when credentials are set, so automatic signing reaches Apple in headless CI with no signed-in Apple ID |
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
| **Version Source — kmp** | Reads and writes `versionName` / `versionCode` in `gradle.properties` for KMP projects that share version values across platforms. |
| **Version Source — gradle** | Reads and writes `versionName` / `versionCode` directly in `build.gradle.kts` or `build.gradle`. Default versioning source for Android projects. |
| **Version Target Override** | The `version` action accepts a `target` option (`source_of_truth`, `project_spec`, or `xcodeproj`) to override the configured versioning source per-step, enabling workflows that write to the spec file even when the default source is `xcodeproj`. |
| **Version dry-run preview** | `shipit version --bump patch --dry-run` shows the current and next version without writing changes. Useful for CI validation and agent verification before committing to a bump. |
| **Safe bump ordering** | When a workflow bumps marketing version (`patch`/`minor`/`major`) and build number in the same run, ShipIt enforces correct ordering: marketing version first (which resets build to 1), then build bump if needed separately. Prevents stale build numbers from a pre-bump read. |
| **Git Tag** | Auto-tag releases with version |
| **Changelog** | Generate from git commits between tags |

### Project Generation

For iOS projects that use spec-driven project tools (XcodeGen, Tuist, etc.), ShipItSwifty can auto-generate the `.xcodeproj` before any Xcode-dependent workflow step.

| Feature | Status | Description |
|---|---|---|
| **Auto-generation** | Implemented | When `project_generation.tool` is configured in Shipfile.yml, `Workflow.run()` automatically generates the Xcode project before the first Xcode-dependent step (build, test, archive, etc.), including when those steps are reached through nested `custom_actions`. Skips generation when the output project already exists. |
| **`generate_project` action** | Implemented | Explicit action for project generation. Supports `command`, `spec_path`, `output_project`, and `force` options. Runs the configured command through `/bin/bash -c` so quoted arguments and non-trivial shell command strings are preserved. |
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
| **Build** | `shipit build --platform android` | `./gradlew assembleRelease` (or configured variant). Gradle output streams live and a build summary is printed even without `--verbose`. |
| **Archive** | `shipit archive --platform android` | `./gradlew bundleRelease` — produces an `.aab`. Gradle output streams live to the console during the (often multi-minute) build, and a build summary (`BUILD SUCCESSFUL …`, the `actionable tasks: … from cache …` cache-effectiveness line, and any build-scan URL) is always printed even without `--verbose`. `--output-path` copies the produced `.aab` to a deterministic path for build/upload job splits. |
| **Test** | `shipit test --platform android` | `./gradlew test` (unit) or `./gradlew connectedAndroidTest` (instrumented). Instrumented runs support connected devices, named AVD boot, and Gradle Managed Devices. |
| **Lint** | `shipit lint --platform android` | `./gradlew lint` |
| **Play Store** | `shipit play-store` | Upload AAB to Google Play via service account JWT auth. Supports per-workflow `build_variant` and `flavor` overrides for artifact path auto-discovery. Requires `track` option on the workflow step. |
| **Validate Bundle** | `shipit validate bundle` | `bundletool validate --bundle` for AABs plus ZIP/size/extension checks for AAB/APK pre-upload validation. Auto-discovers conventional native Gradle, Flutter, and React Native artifact paths when no explicit path is provided. |

### Android Shipfile example

```yaml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp

workflows:
  beta:
    - action: test
    - action: test
      options:
        kind: instrumented
        scope: root
        devices:
          strategy: named_emulators
          emulators: ["Pixel_9_API_35"]
          # prompt_locally: true  # optional local fallback if the configured AVD is unavailable
    - action: archive
    - action: play-store
      options:
        track: internal
```

### Platform-aware commands

All commands accept `--platform ios|android`. When omitted, the platform is auto-detected:
- `gradlew` or `build.gradle.kts` in the root → `.android`
- `*.xcworkspace` or `*.xcodeproj` in the root → `.ios`
- Default → `.ios`

AI session is also platform-aware: `shipit ai-session --goal beta --platform android` returns an Android-specific agent prompt and secret descriptors for Google Play service accounts.

---

## Cross-platform build systems

ShipItSwifty separates **target platform** (`ios`, `android`) from **build system** (`native`, `flutter`, `react_native`, `kmp`). A single Kotlin Multiplatform or Flutter source tree can ship to both stores from one Shipfile.

| Build system | iOS compile step | Android compile step | Distribution pipeline | Status |
|---|---|---|---|---|
| `native` (default) | `xcodebuild` | `gradlew assemble` / `bundle` | App Store Connect / Google Play | ✅ Implemented |
| `kmp` | `gradlew :shared:link…Framework…` → `xcodebuild` against wrapper | `gradlew :androidApp:assembleRelease` / `:androidApp:bundleRelease` | App Store Connect / Google Play (unchanged) | ✅ Implemented |
| `flutter` | `flutter build ipa` (IPA direct, no export step) | build: `flutter build apk`; archive: `flutter build appbundle` | App Store Connect / Google Play (unchanged) | ✅ Implemented |
| `react_native` | Metro bundle → `xcodebuild archive` + export | build: `npx react-native build-android`; archive: `npx react-native build-android --tasks bundleRelease` | App Store Connect / Google Play (unchanged) | ✅ Implemented |

Configure under the relevant Shipfile block:

```yaml
ios:
  build_system: kmp           # native (default) | flutter | react_native | kmp
  scheme: iosApp
  kmp_shared_module: shared
  kmp_build_target: IosSimulatorArm64
  kmp_archive_target: IosArm64
android:
  build_system: kmp
  module: androidApp
  gradle_project_dir: .
versioning:
  source: kmp
  spec_path: gradle.properties
```

Detection is automatic when `build_system` is omitted — see [`docs/configuration-reference.md`](configuration-reference.md#build-systems) for the detection table and CI overrides.

See [`docs/kmp-quickstart.md`](kmp-quickstart.md) for a worked KMP example.

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

## Standalone tool libraries

`XcodeBuildKit`, `GradleKit`, and `XcodeGenKit` are independently consumable via SwiftPM — users who only need build tool wrappers can depend on them without pulling in `ShipItKit`.

### GradleKit tool wrappers

| Wrapper | Capabilities |
|---|---|
| **Gradle** | Task execution, project/system properties, Gradle flags, init scripts |
| **Adb** | Device targeting (`-s`), daemon lifecycle (`start-server`/`kill-server`), device discovery (`devices`), app install/uninstall, activity manager (`am start`, `am force-stop`, deep links), package manager (`pm list`, `pm grant`, `pm revoke`, resolve launchable activity), capture (`screencap`, `screenrecord`), input events (`keyevent`), display config (`uimode night`), port forwarding (`forward tcp`), file transfer (`push`/`pull`), shell escape hatch, emulator control (`emu kill`, `emu geo fix`), logcat |
| **Bundletool** | AAB validation, APK set build, device-spec install |
| **Emulator** | AVD launch, snapshot management |

### XcodeBuildKit tool wrappers

| Wrapper | Capabilities |
|---|---|
| **XcodeBuild** | Build, test, archive, export — typed options and destination discovery |
| **XcodeSelect** | Print/switch active Xcode |

### XcodeGenKit tool wrappers

| Wrapper | Capabilities |
|---|---|
| **XcodeGen** | Project generation from spec files |

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

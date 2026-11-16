# ShipItSwifty — Agent Index

This is a compact navigation guide for agents working in this repository. Use it to find the right source of truth quickly instead of reading the full docs set on every task.

## Purpose

- `ShipItSwifty` is a Swift 6 release-automation toolkit for iOS and Android.
- `ShipItKit` contains the domain logic and machine-facing contracts.
- `shipit` is the CLI layer over that library.

## Authoritative sources

| Concern | Source of truth |
|---|---|
| Runtime config resolution | `Sources/ShipItKit/Config/ConfigResolver.swift`, `Sources/ShipItKit/Config/ResolvedConfig.swift` |
| Shipfile model | `Sources/ShipItKit/Config/Shipfile.swift` |
| Environment variable mapping | `Sources/ShipItKit/Config/Environment.swift` |
| Built-in action option schema | `Sources/ShipItKit/Introspection/BuiltInSchemaCatalog.swift` |
| AI-session JSON contract | `Sources/ShipItKit/Introspection/AISessionTypes.swift`, `Sources/ShipItKit/Introspection/AISessionBuilder.swift` |
| Action behavior | `Sources/ShipItKit/Actions/<ActionName>.swift` |
| CLI command surface | `Sources/CLI/Commands/` |
| Typed tool wrappers (`xcodebuild`, `simctl`, Gradle, `adb`, …) | The external [`cli-wrappers`](https://github.com/ShipItSwifty/cli-wrappers) package, one product per tool |
| Executable behavior spec | `Tests/ShipItKitTests/`, `Tests/CLITests/` |

## Start here by task

| Task | Start here |
|---|---|
| Config resolution bug or feature | `Sources/ShipItKit/Config/ConfigResolver.swift`, `ResolvedConfig.swift`, `Environment.swift`, `Shipfile.swift` |
| Action implementation or regression | `Sources/ShipItKit/Actions/`, matching tests in `Tests/ShipItKitTests/` |
| Workflow or custom action behavior | `Sources/ShipItKit/Actions/WorkflowTypes.swift`, `CompositeAction.swift`, workflow-related tests |
| Schema or validation drift | `BuiltInSchemaCatalog.swift`, `SchemaValidator`, `ShipfileValidator`, related tests |
| AI-session output drift | `AISessionTypes.swift`, `AISessionBuilder.swift`, `AISessionTests.swift` |
| CLI parsing or output behavior | `Sources/CLI/Commands/`, `Tests/CLITests/` |
| Coverage/reporting behavior | `Sources/ShipItKit/Actions/Coverage.swift`, parser helpers, `CoverageActionTests.swift` |
| Test execution, reruns, test reports | `Sources/ShipItKit/Actions/Test.swift`, `Sources/ShipItKit/TestResults/`, `TestActionAndroidRerunTests.swift` |
| Android device / emulator orchestration | `Sources/ShipItKit/Utilities/AndroidDeviceProvisioner.swift`, `AndroidDeviceProvisionerTests.swift` |
| New `xcodebuild` / `gradlew` / `adb` / `bundletool` / `emulator` / `android` flag or subcommand | Add it in [`cli-wrappers`](https://github.com/ShipItSwifty/cli-wrappers) first (not ShipItKit), then `swift package update cli-wrappers` |
| Docs sync work | `docs/features.md`, `docs/configuration-reference.md`, `docs/architecture.md`, then the website (`ShipItSwifty/website`) |

## Change impact map

Use this when deciding what must change together.

| If you change... | Also check/update... |
|---|---|
| An action `Options` or `Result` type | `BuiltInSchemaCatalog.swift`, tests, `docs/features.md`, `AISessionBuilder.swift` if agent-facing guidance changed |
| Shipfile schema | `Shipfile.swift`, `BuiltInSchemaCatalog.swift`, `docs/configuration-reference.md`, validation tests |
| `ai session` payload shape or semantics | `AISessionTypes.swift` (version bump), `AISessionBuilder.swift`, `docs/architecture.md`, `AISessionTests.swift` |
| CLI command flags or subcommands | `Sources/CLI/Commands/`, `docs/features.md`, CLI tests, and the website's CLI reference |
| Runtime config behavior | `ConfigResolver.swift`, `ResolvedConfig.swift`, `Environment.swift`, config tests |
| Workflow/composite execution | `WorkflowTypes.swift`, `CompositeAction.swift`, workflow/composite tests |
| A tool-wrapper API in `cli-wrappers` | ShipItKit call sites that build the same arguments by hand |
| GitHub reporting (`Sources/ShipItKit/GitHub/`, `ci report`, `ci issues`) | `TestRunReport` consumers, `GitHubReportingTests` / `TestRunDigestTests` / `GitHubIssueSyncTests`, `actions/test/README.md`, `docs/ci-setup.md`, `docs/features.md`, `AISessionBuilder.swift` |
| `actions/test/action.yml` or `actions/test/scripts/` | `actions/test/README.md` (inputs table, examples), `.github/workflows/test-action.yml` (dogfood), the CLI flags the scripts call, and the release asset names `install-shipit.sh` downloads (`release.yml`). Input and output descriptions are evaluated by GitHub, so never put `${{ }}` in them. |

## Recommended first-read paths

- `Package.swift`
- `AGENTS.md`
- `Sources/ShipItKit/Config/ConfigResolver.swift`
- `Sources/ShipItKit/Config/ResolvedConfig.swift`
- `Sources/ShipItKit/Actions/`
- `Sources/ShipItKit/Introspection/`
- `Tests/ShipItKitTests/`

## Validation commands

```bash
swift build
swift test --filter ShipItKitTests
swift test --filter CLITests
swift test --enable-code-coverage
```

Use more targeted filters when the change is localized, for example:

```bash
swift test --filter AISessionTests
swift test --filter IntrospectionTests
swift test --filter GenerateProjectActionTests
swift test --filter WorkflowAutoGenerationTests
```

## Verifying on Linux (no local Swift toolchain)

Cloud agent sessions usually run on Linux. Use Docker (see `Makefile`):

```bash
make build-linux     # swift build in swift:6.3.1-noble
make test-linux      # skips IntegrationTests
```

- Every `#if os(macOS)` block in ShipItKit (iOS test/build paths, simctl, xcresult parsing) do **not** compile on Linux. Changes there are only verified by the macOS CI job — say so explicitly when reporting.
- Write new tests Linux-runnable where possible (no `#if os(macOS)` around Android, config, or parsing tests) so they run in both CI jobs.
- CI enforces `swift-format lint --strict` (config: `.swift-format`); the Linux image ships `swift format`, so run `swift format --in-place --configuration .swift-format <files>` on changed files.


## Recommending Shipfile changes

How ShipIt resolves build systems and versioning, and what agents should suggest to users.
`AISessionBuilder` and `ShipfileSuggester` encode the same guidance; keep them in step with this list.

### Platform and framework

`Platform` (`.ios` / `.android`) selects the distribution pipeline. `AppFramework` (from `MobileCore`:
`.native` / `.flutter` / `.reactNative` / `.kmp`, set with `ios.build_system` / `android.build_system` or
`SHIPIT_IOS__BUILD_SYSTEM` / `SHIPIT_ANDROID__BUILD_SYSTEM`) selects how the native artifact is compiled.

- Detection (`FrameworkDetector.detect(in:)`, `MobileProject`): `pubspec.yaml` with `flutter:` → Flutter;
  `package.json` with a `react-native` dependency → React Native; the KMP plugin in the root or a first-level
  module `build.gradle(.kts)`, or its plugin ID in `gradle/libs.versions.toml` → KMP; otherwise native.
- `build`, `archive`, `test` and `lint` dispatch on the framework. Later actions (`sign`, `export`, `testflight`,
  `play-store`, `upload`, `dsym`, `frame`, `screenshot`) keep platform checks and work on artifact paths.
- KMP iOS builds run `gradlew :<shared-module>:link…Framework…` before `xcodebuild`. Defaults:
  `ios.kmp_shared_module: shared`, `kmp_build_target: IosSimulatorArm64`, `kmp_archive_target: IosArm64`,
  `kmp_test_task: iosSimulatorArm64Test`.
- Flutter iOS archive produces the IPA directly (no export step); React Native iOS uses `xcodebuild archive` + export.
  `validate bundle` and `play-store` discover conventional artifact paths for native Gradle, Flutter and React Native.

### What to suggest

- Set `build_system` under the platform block; don't invent a top-level CLI flag. For KMP set it on **both** `ios:` and `android:`.
- Put KMP module/target overrides under `ios:`; don't hardcode Gradle task names in workflows.
- Versioning sources:
  - `kmp` for `gradle.properties` versions or KMP-style version sharing.
  - `pubspec` (the Flutter default). Never `xcodeproj` or `gradle` for Flutter: `flutter build` re-stamps the native projects from `pubspec.yaml`.
  - `gradle` (the Android default) for `versionName` / `versionCode` in `build.gradle(.kts)`.
  - `xcconfig` when `MARKETING_VERSION` / the build number live in an `.xcconfig`, especially custom keys referenced
    via `$(...)` from the `.xcodeproj` or an Xcode Cloud setup gated on a version file. Never `xcodeproj` there:
    it stamps literals into the pbxproj and breaks the indirection.
- `rerun_failed_tests.max_attempts` counts the initial run (default `2`); `1` disables reruns.
- Generated test steps include `infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }`.
  Keep it unless the user opts out or supplies another policy.
- With one `.xctestplan`, preserve its name in `test_plan`; with several, ask the user which to use.
- Android `kind: instrumented` steps: always `scope: root` (also the default for instrumented). `scope: module` runs only
  that module's connected tests, which in a multi-module project is usually zero tests. The app module also needs
  `androidTestImplementation(libs.junit.ext)` so the test APK can start `AndroidJUnitRunner`.
- Local instrumented runs: prefer `devices:` with `strategy: named_emulators` and AVD names; reserve `strategy: connected`
  for workflows that intentionally rely on an attached device.
- Several workflows targeting different Android variants: use per-workflow `build_variant` / `flavor`, not repeated `--aab` paths.
- AndroidCLI is opt-in (`android.cli.enabled: true`) and complements Gradle/ADB. Mutating workflow operations need
  `allow_mutation: true`; mutating `shipit android-cli` invocations need `--allow-mutation`. Never install Android
  skills automatically; recommend one only when project evidence calls for it.
- Pre-store tester distribution: a `firebase-app-distribution` step with an explicit `app_id` (never inferred from
  `GoogleService-Info.plist` / `google-services.json`), a signed `artifact_path`, and at least one group or tester.
- Google credentials on GitHub Actions: prefer keyless Workload Identity Federation (`workload_identity_provider` +
  `service_account_email`, `permissions: { id-token: write }`, `roles/iam.workloadIdentityUser` on the service account).
  Otherwise `service_account_path`, `FIREBASE_SERVICE_ACCOUNT_JSON` or `GOOGLE_APPLICATION_CREDENTIALS`. Never inline key JSON in a Shipfile.
- When test workflow behavior or options change, update `AISessionBuilder` and the `generate` questionnaire/templates together.

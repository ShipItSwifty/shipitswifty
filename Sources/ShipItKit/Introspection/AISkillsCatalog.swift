import Foundation

/// One built-in, curated agent playbook — a short, task-oriented "how to do X with ShipIt"
/// guide distinct from the full reference docs it points into.
///
/// Playbooks are intentionally short: they outline the steps and the exact commands/keys
/// involved, then link to the authoritative doc for full detail, rather than duplicating that
/// doc's content. This keeps them cheap to keep in sync as the underlying feature evolves.
public struct AISkill: Sendable, Equatable {
    public let id: String
    public let title: String
    /// One-line summary shown by `shipit ai skills list`.
    public let summary: String
    /// Full playbook body shown by `shipit ai skills show <id>`.
    public let content: String

    public init(id: String, title: String, summary: String, content: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
    }
}

/// The built-in catalog of agent playbooks surfaced via `shipit ai skills`.
///
/// This is a fixed, in-binary set — not an installable package registry. Adding a playbook
/// here is a documentation change (one more curated guide), not a new subsystem; see
/// `AGENTS.md` before adding one so it stays consistent with the doc it summarizes.
public enum AISkillsCatalog {
    public static let all: [AISkill] = [
        reactNativeSetup,
        firebaseDistribution,
        migrateFromFastlane,
        kmpDualPlatform,
        customActions,
        testWorkflows,
        investigateTestFailures,
    ]

    public static func skill(id: String) -> AISkill? {
        all.first { $0.id == id }
    }

    private static let testWorkflows = AISkill(
        id: "test-workflows",
        title: "Set up and run test workflows",
        summary: "Run package, Xcode, Gradle, Flutter and Jest tests with reruns, evidence and CI export.",
        content: """
            # Set up and run test workflows

            1. Put the checks in a named workflow and select it with `test_workflow: <name>` (or run
               `shipit test --workflow <name>`). Swift packages use `swift-test` (and `swift-format`);
               apps use the `test` action, which runs xcodebuild, Gradle, Flutter or Jest from the
               project's `build_system`.
            2. Add `rerun_failed_tests: { enabled: true, max_attempts: 2 }` to rerun only failures. It
               applies to SwiftPM, Flutter, React Native (Jest), Android JVM and native iOS. A test that
               passes on a rerun is reported flaky, not hidden. Keep the default
               `infrastructure_retry` for simulator, emulator and tool failures.
            3. Native iOS builds once into `.xctestproducts`, then runs every plan and destination. Use
               `test_plans: [Unit, Smoke]` for plans over the same test targets. A simulator clone
               failure falls back to serial once per destination, without rebuilding.
            4. Declare `artifacts:` (name, paths, retention_days) on any step to keep what you need.
               `continue_on_failure: true` is for independent checks only.
            5. `shipit ci export --provider github-actions --workflow <name> --runner <label>` emits a
               job that runs the workflow and publishes evidence even when tests fail. Setup (toolchain
               install) is explicit: pass `--setup-command`.
            6. Gate coverage with `minimum_coverage` and `source_roots`.

            Evidence for every attempt (logs, command.json with durations, results) lands under
            `build/test-runs/<run>/`. Full reference: docs/testing.md and docs/configuration-reference.md.
            """
    )

    private static let investigateTestFailures = AISkill(
        id: "investigate-test-failures",
        title: "Investigate a failed or flaky test run",
        summary: "Triage from the typed report and saved evidence, not the console.",
        content: """
            # Investigate a failed or flaky test run

            1. Open `build/test-runs/<run>/report.json` (or the file written by `--report-path`). For
               saved artifacts without a Shipfile: `shipit test-results --input <path> --output json`
               (add `--runner swift-test` for JUnit from `swift test`, `--build-system kmp` for Kotlin
               Multiplatform).
            2. Read `summary` first. `errored` above zero means the run failed without producing
               results (compile error, crash, no tests found): fix that before looking at tests.
            3. `persistentFailedTests` are real failures: use `message` and `stackTrace`, and
               `destinationID` to see where (`destinations` lists platform, kind, device name and the
               Gradle task or Xcode plan).
            4. `flakyTests` passed only after a retry (`attempts` above 1). `metadata.first_failure` says
               why the first attempt failed. A green run can still contain flaky tests: report them.
            5. `attempts` shows how each execution ended: `reason` (initial, failed_tests,
               infrastructure, serial_fallback), `durationSeconds`, `metadata.overhead_seconds`. A
               `serial_fallback` means a simulator clone failure, not a test failure. `buildSeconds`
               is the shared native build.
            6. Each `attempt-N/` keeps its own stdout.log, stderr.log, command.json and native results
               (xcresult, events.jsonl, JUnit XML, Jest JSON), so an earlier attempt is never lost.
            7. To share evidence, `shipit test-results --input <path> --export-directory <new dir>` writes
               a portable folder with a manifest and index.

            Never edit a report or its evidence to change an outcome. Full reference: docs/testing.md.
            """
    )

    private static let reactNativeSetup = AISkill(
        id: "react-native-setup",
        title: "Set up a React Native or Expo project",
        summary: "Place the Shipfile correctly and archive both platforms.",
        content: """
            # Set up a React Native or Expo project

            1. Run every `shipit` command from the directory holding `package.json` (the RN
               root) — not from `android/` or `ios/`. `build_system` auto-detection reads
               `package.json`, which only exists there.
            2. Generate one Shipfile per platform: `shipit generate --goal beta --platform
               android --non-interactive`, then again with `--platform ios` into a
               differently-named file (e.g. `Shipfile.ios.yml`). A single Shipfile resolves
               only one platform.
            3. Do not set `android.gradle_project_dir` — its RN-aware default already resolves
               to `./android` relative to the Shipfile. Setting it does not relocate where
               Gradle looks for `settings.gradle`; it only selects which `gradlew` script runs.
            4. For managed Expo apps, keep the Shipfile at the RN root even though this differs
               from what generating *from inside* `android/` would produce — `android/` and
               `ios/` are typically gitignored `expo prebuild` output there.
            5. Cap memory on constrained machines: `GRADLE_OPTS="-Dorg.gradle.workers.max=2"`
               plus `android.gradle_properties: { reactNativeArchitectures: arm64-v8a }` to
               build one ABI instead of four.
            6. Archive with `shipit archive --platform <ios|android>`. The Android path falls
               back from `npx react-native build-android` to a direct Gradle bundle
               automatically on managed Expo apps — no configuration needed.

            Full detail: docs/react-native-quickstart.md
            """
    )

    private static let firebaseDistribution = AISkill(
        id: "firebase-distribution",
        title: "Distribute a build via Firebase App Distribution",
        summary: "Pre-store tester distribution for a signed IPA, APK, or AAB.",
        content: """
            # Distribute a build via Firebase App Distribution

            1. Add a `firebase-app-distribution` step to the workflow after `archive` (and
               `export` for iOS): it needs a signed artifact path (`artifact_path`).
            2. Set an explicit `app_id` — never infer it from `GoogleService-Info.plist` or
               `google-services.json`, since a stale file can silently target the wrong
               Firebase project.
            3. Target testers with `groups` (an alias configured in the Firebase console) or a
               literal `testers` email list — at least one is required.
            4. Prefer keyless auth in CI: `workload_identity_provider` +
               `service_account_email`, with `permissions: { id-token: write }` on the GitHub
               Actions job and `roles/iam.workloadIdentityUser` granted on the service account.
               Otherwise use `service_account_path`, `FIREBASE_SERVICE_ACCOUNT_JSON`, or
               `GOOGLE_APPLICATION_CREDENTIALS` — never inline credential JSON in Shipfile.yml.

            Full detail: docs/configuration-reference.md, docs/ci-setup.md
            """
    )

    private static let migrateFromFastlane = AISkill(
        id: "migrate-from-fastlane",
        title: "Migrate a Fastfile to ShipItSwifty",
        summary: "Lane-by-lane mapping from fastlane to shipit workflows.",
        content: """
            # Migrate a Fastfile to ShipItSwifty

            1. Run `shipit generate --goal beta` (or `--goal release`) from the project root —
               it detects an existing `Fastfile` and surfaces a warning to review migrated
               lanes rather than silently replacing them.
            2. Map each lane to a workflow step: `build_app` → `archive` (+ `export`),
               `run_tests` → `test`, `upload_to_testflight` → `testflight`,
               `upload_to_play_store` → `play-store`, `increment_build_number` /
               `increment_version_number` → `version`.
            3. Move `Fastfile` secrets (API keys, keystore passwords) to the documented
               `${ENV_VAR}` names — do not hardcode them into `Shipfile.yml`.
            4. Validate before deleting the Fastfile: `shipit validate yml`, then
               `shipit run <workflow> --dry-run --output json` to compare the resolved step
               list against what the old lane did.

            Full detail: docs/walkthrough.md, ShipItKit.docc "MigratingFromFastlane"
            """
    )

    private static let kmpDualPlatform = AISkill(
        id: "kmp-dual-platform",
        title: "Ship a Kotlin Multiplatform app to both stores",
        summary: "One Shipfile, shared versioning, both App Store and Google Play.",
        content: """
            # Ship a Kotlin Multiplatform (KMP) app to both stores

            1. Set `build_system: kmp` under **both** `ios:` and `android:` — it is detected
               automatically when the Kotlin Multiplatform Gradle plugin is present, but set it
               explicitly if detection is ambiguous (e.g. a version-catalog project).
            2. Use `versioning.source: kmp` to read/write `versionName` / `versionCode` in
               `gradle.properties`, shared by both platforms from one source of truth.
            3. Override module/target names under `ios:` rather than hardcoding Gradle task
               names in workflows: `kmp_shared_module`, `kmp_build_target` (default
               `IosSimulatorArm64`), `kmp_archive_target` (default `IosArm64`),
               `kmp_test_task` (default `iosSimulatorArm64Test`).
            4. `shipit build --platform ios` and `shipit archive --platform ios` automatically
               run `gradlew :<shared-module>:link…Framework…` before `xcodebuild`. No manual
               Gradle invocation is needed.

            Full detail: docs/kmp-quickstart.md
            """
    )

    private static let customActions = AISkill(
        id: "custom-actions",
        title: "Compose a reusable custom action",
        summary: "Package a repeated step sequence as a parameterized composite.",
        content: """
            # Compose a reusable custom action

            1. Before adding a new multi-step sequence to a workflow, check
               `custom_actions:` in the existing Shipfile — a user's declared composites are
               enumerated in `shipit ai session`'s agent prompt specifically so agents reuse
               them instead of duplicating the step sequence.
            2. Declare parameters under `parameters:` (`type`, `required`, `default`); reference
               them inside step `options:` with `{{param.NAME}}` — not `${ENV_VAR}` (Shipfile
               env expansion) or `${{ }}` (GitHub Actions), which use different delimiters on
               purpose.
            3. A custom action's `steps:` may reference built-in actions or other custom
               actions, but composite-to-composite references must be acyclic, and a custom
               action's name must not collide with a built-in action name —
               `shipit validate yml` enforces both.
            4. Invoke it from a workflow exactly like a built-in: `- action: <custom_name>`.

            Full detail: AGENTS.md "Custom actions (composite workflow steps)"
            """
    )
}

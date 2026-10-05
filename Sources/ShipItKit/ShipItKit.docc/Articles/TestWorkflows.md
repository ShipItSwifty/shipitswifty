# Test Workflows

Run package, Xcode, Gradle, Flutter and Jest tests as named workflows with selective reruns, evidence for every
attempt, coverage gates and CI export.

## Overview

A test workflow is an ordinary <doc:Workflows> entry made of test steps. `test_workflow` selects the default one
for `shipit test`, and `shipit test --workflow <name>` selects one explicitly. Direct use of the actions keeps
working.

```yaml
test_workflow: tests
workflows:
  format:
    - action: swift-format
      options: { paths: [Sources, Tests] }
  tests:
    - action: swift-test
      options:
        enable_code_coverage: true
        rerun_failed_tests: { enabled: true, max_attempts: 2 }
        infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }
      artifacts:
        - name: unit-tests
          paths: ["build/test-runs"]
          retention_days: 14
```

## Choosing the action

| Project | Action | Runner |
|---|---|---|
| Swift package | ``SwiftTestAction`` (`swift-test`) and ``SwiftFormatAction`` (`swift-format`, strict and non-mutating) | `swift-test` |
| iOS app | ``TestAction`` | `xcodebuild` |
| Android, KMP | ``TestAction`` | `gradle` |
| Flutter | ``TestAction`` | `flutter-test` |
| React Native | ``TestAction`` | `jest` |

## Selective reruns

`rerun_failed_tests: { enabled: true, max_attempts: 2 }` reruns only the failures. `max_attempts` counts the
initial run. A test that passes on a rerun is reported flaky rather than hidden, and a failure that persists
keeps the workflow failing. It applies to SwiftPM, Flutter, React Native (Jest), Android JVM and native iOS.
SwiftPM reruns reuse the built products (`--skip-build`); Flutter reruns select by name, Jest reruns use
`--testNamePattern`, and Gradle reruns use `--tests`. A runner that cannot select a failed test (Kotlin/Native
targets in a KMP build) reports that rerun as unsupported.

`infrastructure_retry` is separate: it retries a whole invocation after a transient tool, simulator or emulator
failure. Each execution is its own attempt in the report.

## Native iOS

By default the tests are built once into an `.xctestproducts` bundle, then every plan and destination runs with
`test-without-building`, reusing the products for retries. Use `test_plans` for plans over the same test
targets, and `legacy_combined_test: true` for the older single invocation.

- Plans run independently; a failure in one does not stop the others, and a failed shared build blocks them all.
- A recognized simulator clone failure falls back to serial execution once per destination, without rebuilding.
  Ordinary assertion failures never trigger it.
- Each run passes `-collect-test-diagnostics never`: on a failing test `xcodebuild` would otherwise gather a simulator sysdiagnose that can hang for 600 seconds. ShipIt keeps its own device log, screenshot and result-bundle attachments for every attempt.
- Each plan is its own destination (`ios:simulator:iPhone 17:Unit`) and carries its configuration's language and
  region.
- Simulator claims use a shared lease format, so ShipIt never reuses a simulator another tool is driving and
  tears down only devices it booted.

## Evidence

Every attempt keeps its own directory under `build/test-runs/<run>/attempt-N/`: stdout and stderr, `command.json`
(arguments, exit code, start time and `duration_seconds`), the runner's native results (`.xcresult`, saved
events, JUnit XML, Jest JSON) and `results.json`. Saving evidence is best effort and never replaces a test
outcome. See <doc:TestResults> for the report that ties them together.

## Artifacts and CI

Any workflow step, including a custom action's, can declare `artifacts` (`name`, `paths` or globs, and
`retention_days`). Evidence is collected after a failed step too and staged under
`build/workflow-artifacts/<run-id>/` with a manifest. Reports and result locations are collected
automatically; build products (IPAs, AABs, archives) only when declared.

`continue_on_failure: true` lets independent checks all run while the workflow still fails if any check does.
`{{run_id}}` scopes a step's output and artifact paths to one workflow run.

``GitHubActionsProvider`` (through ``CIProvider``) turns a workflow into a runnable job:

```bash
shipit ci export --provider github-actions --workflow tests --runner macos-26 \
  --setup-command "swift build"
```

The job runs the workflow and publishes the evidence with `if: always()`, even when tests fail. Setup is
explicit and nothing runs during export.

## Coverage gates

`minimum_coverage` fails the workflow below a line-coverage percentage; `source_roots` and `exclude_previews`
restrict what counts. SwiftPM writes no coverage file when a test fails, so ShipIt recomputes it from the raw
profiles right after the first attempt, before a rerun adds its own.

## How it is verified

Mocks prove a parser handles what we thought a tool writes. Anything that changes how results are parsed,
counted or reported is also checked against real artifacts and sample projects with scripted outcomes (pass,
fail, skip, flake): a SwiftPM package, a JVM Gradle project with the real `test-retry` plugin, the Flutter and
React Native apps, and an iOS app with two real test plans on a simulator. The matrix, and how to run each layer,
is in `docs/testing.md`.

## Topics

### Actions

- ``SwiftTestAction``
- ``SwiftFormatAction``
- ``TestAction``
- ``TestResultsAction``
- ``CoverageAction``

### Artifacts and CI

- ``ArtifactDeclaration``
- ``WorkflowArtifactRecord``
- ``CIProvider``
- ``GitHubActionsProvider``
- ``CIProviderRegistry``
- ``CIJobConfiguration``

### Results

- <doc:TestResults>
- ``TestRunReport``
- ``TestAttempt``

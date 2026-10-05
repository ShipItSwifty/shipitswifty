# Test Results

Read, compare and export structured test results from every supported runner, live or from saved artifacts.

## Overview

Every test run, and every saved result file, is read into the same normalized model. That is what lets a
workflow decide whether to rerun a failure, lets `shipit test-results` inspect an artifact on a machine that
never ran the tests, and lets a live run and an offline inspection agree on every test's identity.

The core public types are ``ParsedTestRun``, ``ParsedTestCase``, ``ParsedTestSuite``, ``TestRunReport`` and
``TestAttempt``. ``ResultInspection`` is the single reader for every format.

## Who ran it, where, and on what

A result separates three things that used to be squeezed into one label:

| Field | Meaning | Values |
|---|---|---|
| `runner` (``TestRunner``) | The tool that executed the tests | `xcodebuild`, `gradle`, `swift-test`, `flutter-test`, `jest` |
| `buildSystem` (``BuildSystem``) | The project's framework, when known | `native`, `kmp`, `flutter`, `react_native` |
| `destinations` (``TestDestination``) | Where the tests ran | a ``TestPlatform`` (`ios`, `android`, `macos`, `linux`, `windows`, `jvm`, `js`), a ``TestDestinationKind`` (`simulator`, `emulator`, `device`, `host`), an optional device name, and the scope that ran (a Gradle task or an Xcode test plan) |

Each test refers to its destination by `destinationID`, so one Gradle run on a Kotlin Multiplatform project
can span `ios`, `android` and `jvm` and every test still knows which. Destinations come from evidence: the
Gradle task name and the device the Android Gradle Plugin records, the devices an `.xcresult` lists, the
`xcodebuild -destination` and test plan, or the host for `swift test`, Flutter and Jest. A result that does not
say where it ran (saved Flutter events, an LCOV file) has no destination rather than a guess.

``TestPlatform`` and ``TestRunner`` are closed for the values ShipIt understands but keep any other value as
`other`, so a result from a plugin or a newer ShipIt still decodes and groups correctly.

## What each test carries

- `status`: `passed`, `failed`, `skipped`, `flaky` or `errored`. An `errored` test (or run) did not produce a
  result, which is different from a test that failed.
- `message` and `stackTrace`, kept apart.
- `attempts`: how many times the runner executed it, retries included. A test that passed with more than one
  attempt is **flaky** even though the run is green; `metadata["first_failure"]` says why it first failed.
- `durationSeconds` is the deciding attempt and `totalDurationSeconds` is what every attempt cost.
- `metadata`: `module`, `gradle_task`, `plan`, `configuration`, `language`, `device`, `flaky` and more, only
  where the runner reported them.
- A stable `stableID` that is the same on every machine and across attempts, so a selective rerun and its
  reconciliation line up.

Retry plugins write one entry per attempt. When a repeated name includes a failure those entries are folded
into one test, and the totals the suite declares (which count every attempt) are restated for the folded view.

## Attempts, flakiness and where the time went

``TestRunReport`` is the machine-readable record of a whole run. Its `attempts` array (``TestAttempt``) records
each execution: its `reason` (`initial`, `failed_tests`, `infrastructure`, `serial_fallback`), its summary, the
failures it saw, `durationSeconds`, and `metadata` such as `overhead_seconds` (everything around the test
command: reinstalling the app, reading the result bundle). `buildSeconds` is the shared build for runners that
build once and test many times. `summary.flaky` and `flakyTests` count every test that passed only after a
retry, whether the workflow's own rerun or the runner's retry plugin recovered it.

`report.json` always describes the whole run. If a run stops before the final report is written, a provisional
one is written from the attempts recorded so far, with one extra `errored` so it can never read as a pass.

A run that exits 0 without reporting any results is a failure, not a passing zero-test run. Gradle's
`NO-SOURCE` or `SKIPPED` for the test task is the one legitimate empty run.

## Reading saved artifacts

`shipit test-results` and ``ResultInspection`` read an artifact without running anything:

```bash
shipit test-results --input results.xcresult --export-directory artifacts/ios
shipit test-results --input app/build/test-results/testDebugUnitTest --runner gradle
shipit test-results --input shared/build/test-results --runner gradle --build-system kmp
shipit test-results --input flutter-events.jsonl --input-format flutter
shipit test-results --input swift-events.jsonl --input-format swift
shipit test-results --input jest.json --input-format jest
shipit test-results --input artifacts/ios/manifest.json --format markdown
```

| Format (``TestInputFormat``) | Source |
|---|---|
| `xcresult` | An `.xcresult` bundle, read through `xcresulttool` (macOS) |
| `junit` | Gradle, KMP or `swift test` JUnit XML. Pass `--runner swift-test` for the latter and `--build-system kmp` for Kotlin Multiplatform, because the file alone does not say |
| `swift` | Swift Testing's saved event stream |
| `flutter` | `flutter test --machine` events |
| `jest` | `jest --json --outputFile` |
| `shipit` / `manifest` | A ShipIt report, or a portable export |

Test identities are relative to the project (the Gradle root, or the directory holding `package.json`) so they
are the same offline as in a live run. Filtering the displayed cases never changes the full-run summary.

## Portable evidence

Add `--export-directory` (and `--evidence`, `--coverage-input`) to write a **new** directory holding normalized
results, coverage, the original artifacts, extracted xcresult attachments, diagnostics and logs, a manifest and
an index with relative links. ``EvidenceExporter`` builds it in a hidden sibling directory and renames it into
place only when complete, follows symbolic links so the export holds real files, and never overwrites an
existing export. `results.json` and `coverage.json` carry a `schemaVersion`.

## Coverage

``PortableCoverageReader`` reads SwiftPM LLVM JSON, LCOV and JaCoCo/Kover XML (``CoverageInputFormat``).
Coverage results carry the same typed `platform` and a `runner` naming whose format they are; reports are listed
side by side and never summed. See <doc:Coverage>.

## Example

```swift
let run = try await ResultInspection(shell: context.shell)
    .read("./build/MyApp-tests.xcresult")

print(run.runner, run.destinations.map(\.id))
for test in run.testCases where (test.attempts ?? 1) > 1 && test.status == .passed {
    print("flaky:", test.name, test.attempts ?? 1)
}
```

## Verified against real tools

The parsers are tested against artifacts captured from real runs (Gradle with the `test-retry` plugin,
`xcodebuild`, `flutter test --machine`, `jest --json`) and the workflows are exercised end to end against
sample projects with scripted outcomes. See <doc:TestWorkflows>.

## Topics

### Models

- ``ParsedTestRun``
- ``TestSummary``
- ``ParsedTestSuite``
- ``ParsedTestCase``
- ``TestCaseStatus``
- ``TestRerunSelector``
- ``ParsingDiagnostic``
- ``ParsingDiagnosticSeverity``
- ``TestRunReport``
- ``TestAttempt``

### Where tests ran

- ``TestRunner``
- ``TestPlatform``
- ``TestDestination``
- ``TestDestinationKind``
- ``OpenStringEnum``

### Reading and exporting

- ``ResultInspection``
- ``TestInputFormat``
- ``EvidenceExporter``
- ``EvidenceManifest``
- ``EvidenceEntry``
- ``PortableCoverageReader``
- ``CoverageInputFormat``

### Protocols

- ``TestResultParser``
- ``TestArtifactLocator``
- ``TestRerunPlanner``
- ``TestParseContext``
- ``TestArtifact``
- ``TestArtifactKind``

### Native parsers

- ``IOSXCResultTestParser``
- ``AndroidJUnitTestParser``
- ``JestJSONTestParser``
- ``FlutterMachineOutputParser``

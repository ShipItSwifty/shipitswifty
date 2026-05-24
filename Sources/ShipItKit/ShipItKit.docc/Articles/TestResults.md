# Test Results

Read structured test results from existing iOS, Android, Flutter, and React Native artifacts.

## Overview

ShipItKit exposes a reusable parsing surface for test artifacts so Swift tools, CI pipelines,
 and the `shipit` CLI can all consume the same normalized model.

The core public types are:

- ``ParsedTestRun``
- ``ParsedTestCase``
- ``ParsedTestSuite``
- ``TestRunReport``
- ``TestResultParser``
- ``TestArtifactLocator``
- ``TestRerunPlanner``

Use this article together with <doc:ActionsCatalog> and <doc:OutputFormats>.

## Current status

The shared result model is available as a public SwiftPM surface.
Parser implementations, the `shipit test-results` command, rerun orchestration,
and tutorials are documented here as they land.

## Example

```swift
let run = ParsedTestRun(
    platform: "ios",
    runner: "xcodebuild",
    source: "./build/MyApp-tests.xcresult",
    summary: TestSummary(passed: 42, failed: 1, skipped: 0)
)

let report = TestRunReport(
    platform: run.platform,
    runner: run.runner,
    source: run.source,
    summary: run.summary
)
```

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

### Protocols

- ``TestResultParser``
- ``TestArtifactLocator``
- ``TestRerunPlanner``
- ``TestParseContext``
- ``TestArtifact``
- ``TestArtifactKind``

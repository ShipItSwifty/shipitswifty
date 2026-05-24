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
Native parsers currently cover:

- iOS `.xcresult` bundles via `xcresulttool`
- Android Gradle JUnit XML reports

The `shipit test-results` command, rerun orchestration, and tutorials are
documented here as they land.

## Example

```swift
let iosParser = IOSXCResultTestParser(shell: context.shell)
let run = try await iosParser.parse(xcresultPath: "./build/MyApp-tests.xcresult")

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

### Native parsers

- ``IOSXCResultTestParser``
- ``AndroidJUnitTestParser``

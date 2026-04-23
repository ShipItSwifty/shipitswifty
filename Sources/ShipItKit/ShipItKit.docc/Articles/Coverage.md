# Coverage

Read and summarise native iOS and Android coverage artifacts with ``CoverageAction``.

## Overview

ShipItKit does **not** generate coverage data itself — it wraps and normalises the artifacts your platform toolchain already produces:

- **iOS** — `.xcresult` bundles created by `xcodebuild test -enableCodeCoverage YES`.
- **Android** — JaCoCo XML reports created by Gradle's `jacocoTestReport` task.

Both produce identical ``CoverageAction/Result`` shapes, so downstream tooling (PR comment bots, dashboards, CI gates) only has to learn one schema.

## CLI quick reference

```bash
shipit coverage                                              # auto-discover, first-party default
shipit coverage --first-party-only --targets                # per-target summary
shipit coverage --files                                     # per-file breakdown
shipit coverage --format json                               # machine-readable
shipit coverage --format markdown                           # PR comment / CI summary
shipit coverage --summary                                   # single overall line
shipit coverage --xcresult ./build/MyApp-tests.xcresult     # iOS explicit path
shipit coverage --platform android                          # Android (JaCoCo XML)
shipit coverage --platform android \
                --report ./app/build/reports/jacoco/test/jacocoTestReport.xml
shipit coverage --include-target MyFeatureKit                # explicit include
shipit coverage --exclude-target GoogleSignIn                # explicit exclude
shipit coverage --sort name --limit 10                       # alphabetical, capped
```

## First-party filtering

By default, ``CoverageAction`` filters to **first-party targets only** so vendored frameworks, Swift-package dependencies, and test bundles don't dilute the headline number. Override with `--include-target` / `--exclude-target` (CLI) or `includeTargets` / `excludeTargets` (Swift) when you want to broaden or pin the set.

## Output formats

| Format | Use case |
|---|---|
| `text` (default) | Terminal-friendly summary |
| `markdown` | Drop into a PR comment or CI step summary |
| `json` | Stable shape for dashboards, gates, agents |

JSON example (truncated):

```json
{
  "action": "coverage",
  "status": "success",
  "payload": {
    "overallLineCoverage": 78.4,
    "platform": "ios",
    "modules": [
      { "name": "MyAppKit", "lineCoverage": 84.1, "lines": 4210, "covered": 3540 },
      { "name": "MyApp",    "lineCoverage": 67.2, "lines": 1880, "covered": 1264 }
    ]
  }
}
```

## Programmatic use

```swift
// iOS — auto-discover xcresult from config
let result = try await CoverageAction().run(
    with: .init(firstPartyOnly: true, format: .text),
    context: context
)
print("Overall: \(result.overallLineCoverage)%")

// Android — explicit report path
let result = try await CoverageAction().run(
    with: .init(reportPath: "./app/build/reports/jacoco/test/jacocoTestReport.xml"),
    context: androidContext
)
for module in result.modules {
    print("\(module.name): \(module.lineCoverage)%")
}
```

## CI integration

Coverage is most useful when wired into your PR feedback loop:

```bash
shipit test --enable-code-coverage
shipit coverage --format markdown >> "$GITHUB_STEP_SUMMARY"
shipit coverage --format json --summary
```

For a hard CI gate:

```bash
THRESHOLD=70
ACTUAL=$(shipit coverage --format json --summary | jq '.payload.overallLineCoverage')
if (( $(echo "$ACTUAL < $THRESHOLD" | bc -l) )); then
  echo "Coverage $ACTUAL% below threshold $THRESHOLD%" >&2
  exit 1
fi
```

## See also

- ``CoverageAction``
- ``CoverageTarget``
- ``CoverageFile``
- ``CoverageFormat``
- ``CoverageSort``
- <doc:CIIntegration>
- <doc:OutputFormats>

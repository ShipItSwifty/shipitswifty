# ShipIt Test (GitHub Action)

Build an iOS project once, run its tests on as many simulators as you like **without rebuilding**, retry failing
tests, and get the result back as a job summary, pull-request annotations and GitHub issues.

The action is a thin wrapper over the `shipit` CLI. Retries, flaky classification, the pass/fail policy, the summary
and the issue logic all live in the CLI (`shipit test`, `shipit ci report`, `shipit ci issues`), so every step can be
run and tested locally. Run it on `macos-*` runners.

```yaml
- uses: ShipItSwifty/shipitswifty/actions/test@<version>   # a bare SemVer tag, e.g. 0.8.0 — no "v"
  with:
    scheme: MyApp
```

The action downloads the `shipit` release with the same version as the tag you pin, and verifies it against the
release's published checksums. Pin to a commit or a branch and it builds `shipit` from its own checkout instead.

## Modes

| `mode` | What it does |
|---|---|
| `full` (default) | Build for testing, run the tests, retry, report. One job. |
| `build-for-testing` | Build once and upload the test products (`.xctestproducts`) as an artifact. Runs no tests. |
| `test-without-building` | Download the test products and run the tests from them. No build. Retry, report. |
| `report` | Merge `report.json` files from other jobs into one summary, one verdict and one set of issues. |

## Sharding: one build, N test jobs

```yaml
name: Tests
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - run: sudo xcode-select -s /Applications/Xcode_26.4.app
      - uses: ShipItSwifty/shipitswifty/actions/test@<version>
        with:
          mode: build-for-testing
          scheme: MyApp
          destination: 'platform=iOS Simulator,name=iPhone 17,OS=26.4'

  test:
    needs: build
    runs-on: macos-26
    strategy:
      fail-fast: false
      matrix:
        shard: [UnitTests, FeatureTests, UITests]
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - run: sudo xcode-select -s /Applications/Xcode_26.4.app
      - uses: ShipItSwifty/shipitswifty/actions/test@<version>
        with:
          mode: test-without-building
          scheme: MyApp
          destination: 'platform=iOS Simulator,name=iPhone 17,OS=26.4'
          only-testing: MyAppTests/${{ matrix.shard }}   # a target, a class, or Target/Class/method; one per line
          artifact-suffix: ${{ matrix.shard }}           # unique per matrix entry
          max-attempts: 3

  report:
    needs: test
    if: always() && needs.test.result != 'skipped'
    runs-on: macos-26   # the report job needs the same shipit; macOS and Linux x86_64 are supported
    permissions:
      contents: read
      issues: write      # only needed with file-issues: true
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: actions/download-artifact@v8
        with:
          pattern: shipit-report-*
          path: shipit-reports
      - uses: ShipItSwifty/shipitswifty/actions/test@<version>
        with:
          mode: report
          file-issues: 'true'
          fail-on-flaky: 'false'
```

Each test shard fails or passes on its own and uploads a `shipit-report-<suffix>` artifact. The `report` job merges
them, so the issue logic runs once and shards never race to edit the same issue.

Keep `destination` identical in the build and test jobs: the products are built for it. Pin it for reproducible runs;
left empty, ShipIt picks a simulator the same way on both jobs, which works while both run on the same runner image.

## Retries and flaky tests

| | |
|---|---|
| **Flaky** | Failed in an attempt, passed on a retry. Reported in the summary and as a warning annotation; passes the job unless `fail-on-flaky: 'true'`. |
| **Consistently failing** | Failed in every attempt (`max-attempts`, counting the first run). Fails the job, annotated as an error, and filed as an issue. |
| **Run error** | The run itself broke: a build failure, a crashed runner, no results. Fails the job. |

`max-attempts` reruns only the failed tests. `infrastructure-retry-attempts` separately retries a whole invocation
after a transient simulator or runner failure (with backoff). Before a rerun, a simulator that stopped answering is
restarted — never erased — so a retry does not inherit a hung device.

## Issues

With `file-issues: 'true'` the action keeps GitHub issues in step with the runs:

- **One issue per consistently failing test**, found again by a hidden fingerprint in its body (runner + test plan +
  the runner's own test id), so reruns and re-sharding never file a second one. A recurring failure edits the issue
  silently; it does not comment on every run.
- **A closed issue reopens** when its test fails again, with one comment.
- **An issue closes** after `close-after-clean-runs` (default 3) consecutive runs in which the test passed with no
  retry. A shard that did not run the test says nothing about it; rerunning the same workflow run does not count twice.
- **One rolling "Flaky tests" issue** lists every flaky test and how many runs it flaked in. A test leaves the list
  after the same number of clean runs; the issue closes when the list is empty.
- Issues hold test ids, plans and links only. Never failure messages, stack traces or logs: read those from the run's
  evidence artifact (linked from the issue).
- Issues are filed only when the run is on `issues-ref` (default: the repository's default branch), so pull requests
  and feature branches never file them. They still get annotations and the summary.

Labels: every issue carries `shipit-test-failure` (failures) or `shipit-flaky-tests` (the rolling issue), which is how
later runs find them, plus whatever you add with `issue-labels`.

### Permissions

The action needs nothing beyond what the checkout needs unless it files issues:

| Permission | When |
|---|---|
| `contents: read` | Always (checkout). |
| `issues: write` | Only with `file-issues: 'true'`, and only on the job that files them. |

It never needs `pull-requests: write`: annotations are written to the job log, not through the API. A failure to
file issues (a token without `issues: write`) is a warning and never changes the test verdict.

## Inputs

| Input | Default | |
|---|---|---|
| `mode` | `full` | `build-for-testing`, `test-without-building`, `full` or `report`. |
| `scheme` | | Xcode scheme. Required except in `report` mode. |
| `workspace`, `project` | | Path to the `.xcworkspace` / `.xcodeproj`, when the scheme lives in one. No Shipfile is needed. |
| `destination` | | xcodebuild destination string. |
| `configuration` | `Debug` | Build configuration. |
| `test-plan` | | `.xctestplan` to run. |
| `only-testing`, `skip-testing` | | Newline-separated identifiers. Use `only-testing` to shard. |
| `max-attempts` | `2` | Attempts for a failing test, counting the first run. `1` disables reruns. |
| `infrastructure-retry-attempts` | `3` | Attempts for a transient simulator/runner failure. `1` disables. |
| `fail-on-flaky` | `false` | Fail the job on a test that passed only on a retry. |
| `test-products-artifact` | `shipit-test-products` | Artifact that carries the products between jobs. |
| `artifact-suffix` | `${{ github.job }}` | Makes artifact names unique. **Set it per matrix entry.** |
| `report-glob` | `shipit-reports/**/report.json` | `report` mode: which reports to merge. |
| `file-issues` | `false` | File and update issues. |
| `issues-ref` | default branch | Only file issues on this branch. |
| `issue-labels` | | Comma-separated extra labels. |
| `close-after-clean-runs` | `3` | Clean runs before an issue closes; `0` never closes. |
| `github-token` | `${{ github.token }}` | Token for issues. |
| `working-directory` | `.` | Directory to run in. |
| `shipit-version` | the pinned tag | `shipit` release to use. |
| `shipit-path` | | A ready `shipit` binary; skips the download and the build. |
| `cache-swiftpm` | `true` | Cache SwiftPM's package cache. DerivedData is never cached: its incremental state is not valid across checkouts, and `build-for-testing` products replace it. |
| `retention-days` | `14` | Retention for the products and evidence artifacts. |

## Outputs

| Output | |
|---|---|
| `passed`, `failed`, `flaky` | Counts. Flaky tests are also in `passed`, as they passed in the end. |
| `has-consistent-failures` | `'true'` when a test failed in every attempt. |
| `policy-passed` | `'true'` when the run passes ShipIt's policy (see `fail-on-flaky`). |
| `report-path` | The merged result JSON from `shipit ci report`. |
| `test-report-path` | The `TestRunReport` JSON from `shipit test`. |
| `test-products-artifact` | Name of the uploaded products artifact. |
| `evidence-artifact-url` | URL of the uploaded logs and result bundles. |

The action decides pass/fail from ShipIt's policy: the job fails when `shipit test` failed or the run does not pass
the policy.

## Running it locally

Every step is a CLI command:

```bash
shipit test --scheme MyApp --build-for-testing-only --test-products-path build/MyApp.xctestproducts
shipit test --scheme MyApp --use-test-products build/MyApp.xctestproducts \
  --only-testing MyAppTests/CartTests --rerun-failed-tests --max-rerun-attempts 3 \
  --infrastructure-retry-attempts 3 --report-path build/report.json
shipit ci report --report build/report.json --annotations --result-path build/result.json
shipit ci issues --report build/report.json --repository owner/name --only-ref main --dry-run
```

## Known limits

- Native iOS only. Other platforms keep using `shipit run <workflow>` and `shipit ci export`.
- Annotations carry a file and line only when the runner reports them; today the Xcode result parser does not read the
  location Xcode attaches to a failure, so failures annotate the run instead of a source line.
- Test products are tarred for upload (a plain artifact upload drops file permissions and symlinks). Run the shards
  on the same Xcode version as the build job.

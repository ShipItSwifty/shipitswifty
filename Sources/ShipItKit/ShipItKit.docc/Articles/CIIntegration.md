# CI Integration

Run ShipItSwifty on GitHub Actions, GitLab CI, Bitrise, Xcode Cloud, and any other CI.

## Overview

ShipItSwifty is built for CI from day one:

- A single binary (`shipit`) does the entire pipeline.
- Every command supports `--ci`, `--output json`, and `--dry-run`.
- All credentials come from environment variables — never from interactive prompts.
- Exit codes are stable and documented (see <doc:ErrorHandling>).
- JSON output is never colorized, so it's safe to pipe into downstream tools.

## Universal patterns

### `--ci` flag

```bash
shipit run beta --ci --output json
```

`--ci` enables non-interactive, strict-error mode:

- Disables interactive prompts.
- Fails on any deprecation warning that would otherwise be a soft warning.
- Sets a sensible default `--color never` for clean logs.

### Dry-run as a smoke test

Before actually running a workflow on CI, agents and pipelines can verify the plan:

```bash
shipit validate yml
shipit run beta --dry-run --output json
```

Both are fast and have no side effects.

## GitHub Actions

### iOS beta

```yaml
name: Beta
on: { push: { branches: [main] } }

jobs:
  beta:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v6
      - uses: maxim-lobanov/setup-xcode@v2
        with: { xcode-version: '26.4' }
      - name: Install shipit
        run: |
          git clone https://github.com/shipitswifty/shipitswifty /tmp/shipit
          cd /tmp/shipit && swift build -c release
          sudo cp .build/release/shipit /usr/local/bin/shipit
      - name: Validate
        run: shipit validate yml
      - name: Run beta
        run: shipit run beta --ci --output json
        env:
          ASC_KEY_ID:       ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID:    ${{ secrets.ASC_ISSUER_ID }}
          ASC_PRIVATE_KEY:  ${{ secrets.ASC_PRIVATE_KEY }}
          VAULT_PASSWORD:   ${{ secrets.VAULT_PASSWORD }}
```

### Android beta

```yaml
jobs:
  beta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v5
        with: { distribution: 'temurin', java-version: '17' }
      # … install shipit …
      - run: shipit run beta --ci --output json
        env:
          GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.GOOGLE_PLAY_JSON }}
```

### Coverage in PR comments

```yaml
- run: shipit test --enable-code-coverage
- run: shipit coverage --format markdown >> "$GITHUB_STEP_SUMMARY"
- run: shipit coverage --format json --summary
```

### Coverage gate

```yaml
- name: Enforce coverage threshold
  run: |
    THRESHOLD=70
    ACTUAL=$(shipit coverage --format json --summary | jq '.payload.overallLineCoverage')
    awk -v a="$ACTUAL" -v t="$THRESHOLD" 'BEGIN { exit (a < t) }' \
      || { echo "::error::Coverage $ACTUAL% < $THRESHOLD%"; exit 1; }
```

## GitLab CI

```yaml
beta:
  image: macos-26-xcode-26
  variables:
    LANG: en_US.UTF-8
  script:
    - shipit validate yml
    - shipit run beta --ci --output json
  variables:
    ASC_KEY_ID:      $ASC_KEY_ID
    ASC_ISSUER_ID:   $ASC_ISSUER_ID
    ASC_PRIVATE_KEY: $ASC_PRIVATE_KEY
```

## Bitrise

Use the Script step:

```bash
#!/usr/bin/env bash
set -euo pipefail
shipit doctor
shipit run beta --ci --output json
```

Inject `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, and `VAULT_PASSWORD` via Bitrise secrets.

## Xcode Cloud

ShipItSwifty runs from a `ci_scripts/ci_post_clone.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
brew install swift
git clone https://github.com/shipitswifty/shipitswifty /tmp/shipit
(cd /tmp/shipit && swift build -c release)
/tmp/shipit/.build/release/shipit run beta --ci --output json
```

## Secret hygiene

- **Never** commit `.p8` keys, vault passwords, or service-account JSON. ShipItKit refuses to read `VAULT_PASSWORD` from Shipfile fields.
- Prefer `*_PATH` env vars locally, and inline `*_JSON` / `*_PRIVATE_KEY` env vars on CI.
- `shipit env` masks secret values in its output.

## Caching

For incremental CI speed:

| Cache | Path | Tool |
|---|---|---|
| Swift build of `shipit` itself | `/tmp/shipit/.build` | actions/cache |
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | actions/cache |
| Gradle | `~/.gradle/caches` | gradle/actions |

## Observability

- `--output json` is the canonical CI format — pipe it to `jq` for assertions.
- Set `--verbose` when debugging a failing run.
- `shipit doctor` reports the detected toolchain, credentials, and Shipfile state.

## See also

- <doc:OutputFormats>
- <doc:ErrorHandling>
- <doc:Coverage>
- <doc:Validation>
- <doc:CodeSigningAndVault>

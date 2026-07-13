# CI Setup

> **DocC mirror:** Also available as the `CIIntegration` article in the `ShipItKit` DocC archive.

How to run ShipItSwifty in GitHub Actions and other CI systems.

## GitHub Actions

The repository includes two pre-built workflows:

| Workflow | File | Trigger |
|---|---|---|
| Build & Test | `.github/workflows/ci.yml` | Push / PR to `main` |
| Build DocC | `.github/workflows/docc.yml` | Push to `main` + manual |

The `Build & Test` workflow runs three jobs in parallel after lint passes:

| Job | Runner | Swift image | Scope |
|---|---|---|---|
| `build-and-test` | `macos-26` | Xcode 26.4 | Main build, unit tests, CLI tests, native integration sweep (broad integration remains non-blocking) |
| `cross-platform-fixture-integration` | `macos-26` | Xcode 26.4 | Blocking Flutter + React Native + KMP fixture integration suites using in-repo tool shims |
| `build-and-test-linux` | `ubuntu-24.04` | `swift:6.3.1-noble` | Skips `XcodeBuildKitTests`, `XcodeGenKitTests`, `IntegrationTests` |

### SwiftyShell dependency

ShipItSwifty depends on the remote `SwiftyShell` Swift package. CI runners must have network and authentication access to fetch Swift package dependencies during `swift build` and `swift test`.

### Required Secrets

For App Store Connect API actions, CI needs `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY`.

`ASC_PRIVATE_KEY` must be the raw contents of the downloaded `.p8` file. `ASC_ISSUER_ID` comes from the App Store Connect API Keys page, not from the key file.

If your CI only runs local validation like `swift test`, `shipit build`, `shipit test`, `shipit archive`, or `shipit export`, you can skip these ASC secrets.

Add these under **Settings → Secrets → Actions**:

| Secret | Description |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_PRIVATE_KEY` | Raw `.p8` key contents (no file path in CI) |
| `SHIPIT_TEST_P12_BASE64` | Base64-encoded development `.p12` for signing integration tests |
| `SHIPIT_TEST_P12_PASSWORD` | Export password for the `.p12` above |

`SHIPIT_TEST_P12_BASE64` and `SHIPIT_TEST_P12_PASSWORD` are only needed if you want the signing
integration tests to run in CI. Without them, those tests skip automatically.

To produce the base64 value from a `.p12` file:

```bash
# Copies the base64-encoded certificate to your clipboard — paste as the secret value
base64 -i MyCert.p12 | pbcopy
```

See `CONTRIBUTING.md` for full signing credential setup instructions.

### Example release workflow

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      workflow:
        description: "Workflow to run (beta or release)"
        required: true
        default: beta

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Install shipit
        run: brew install shipitswifty/tap/shipit

      - name: Run workflow
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
        run: shipit run ${{ github.event.inputs.workflow }} --ci --output json
```

## Basic CI Steps

```bash
brew install shipitswifty/tap/shipit
shipit doctor --ci
shipit test --ci
shipit run beta --ci --output json
```

If your CI stores the config at a non-default path, pass it explicitly:

```bash
shipit doctor --ci --shipfile ./config/Shipfile.ci.yml
shipit run beta --ci --output json --shipfile ./config/Shipfile.ci.yml
```

## JSON Output in CI

Use `--output json` for machine-readable results:

```bash
shipit run beta --ci --output json | jq .status
```

## Writing your own CI script

You have two ways to drive a release from CI. Prefer the first; reach for the second only when a step must live in shell.

### Approach 1 — One Shipfile workflow, one command (recommended)

Put the whole pipeline — build, upload, version bump, commit, and tag — in a `Shipfile.yml` workflow and invoke it with a single `shipit run`. This is the only way to get `commit`/`tag`/`push` as managed steps, because **`git` is a workflow action, not a standalone CLI subcommand** (there is no `shipit git`).

```yaml
# Shipfile.yml
workflows:
  release:
    - action: archive
      options: { configuration: Release, export_method: app-store }
    - action: export
    - action: upload
      options: { submit_for_review: true }
    - action: version              # bump only after upload succeeds
      options: { bump: patch }
    - action: git
      options:
        operation: commit          # stages all changes (git add -A) then commits
        commit_message: "chore: release v{{version}} [skip ci]"   # {{version}} from the step above
    - action: git
      when: "{{version_changed}}"   # skipped on build-only bumps
      options:
        operation: tag
        tag_name: "v{{version}}"    # resolved from the version step — no shell glue
    - action: git
      options:
        operation: push
        push_tags: true
```

```bash
#!/usr/bin/env bash
set -euo pipefail

# Git identity for the commit the `git` action will create.
git config user.name  "ci-bot"
git config user.email "ci-bot@users.noreply.github.com"

shipit doctor --ci
shipit run release --ci --output json | tee result.json
test "$(jq -r '.status' result.json)" = "success"
```

A non-zero exit from `shipit run` already fails the job; the `jq` status check is a belt-and-suspenders guard for pipelines that swallow exit codes.

> **Tagging:** the `tag` step derives its name from the version you just bumped via the `{{version}}` token — no shell parsing or `${ENV_VAR}` round-trip needed. `{{build_number}}` is also available (e.g. `tag_name: "v{{version}}+{{build_number}}"`), and `{{version_changed}}` lets you skip the tag on build-only bumps with `when: "{{version_changed}}"`. See the "Workflow tokens & step conditions" section of `docs/configuration-reference.md`. `shipit generate --goal release` scaffolds this whole tail for you.

### Approach 2 — Hand-rolled shell script

When you need shell-level control (extra tooling between steps, bespoke conditional logic, or values ShipIt doesn't expose as a token), drive the individual subcommands and parse their JSON. Tagging with the freshly bumped version no longer requires this — use the `{{version}}` token in Approach 1. Each `shipit` subcommand emits the envelope `{ "action", "status", "payload": { … } }` and exits non-zero on failure.

```bash
#!/usr/bin/env bash
set -euo pipefail

git config user.name  "ci-bot"
git config user.email "ci-bot@users.noreply.github.com"

shipit doctor --ci

# Build and distribute.
shipit archive --ci --output json
shipit export  --ci --output json
shipit upload  --ci --output json

# Bump the version, then read the new values straight from the JSON payload.
bump_json="$(shipit version --bump patch --ci --output json)"
new_version="$(jq -r '.payload.version'     <<<"$bump_json")"
new_build="$(  jq -r '.payload.buildNumber' <<<"$bump_json")"
echo "Bumped to ${new_version} (${new_build})"

# Commit and tag with plain git — there is no `shipit git` subcommand.
# `shipit version` writes the bump to disk; `git add -A` stages it.
git add -A
git commit -m "chore: release ${new_version} [skip ci]"
git tag -a "v${new_version}" -m "Release ${new_version}"
git push origin HEAD --follow-tags
```

Why this shape:

- **`set -euo pipefail`** — fail the script the instant any `shipit` step or `jq` parse fails, instead of pushing a tag for a build that never uploaded.
- **`--output json`** — every step stays machine-readable so you can gate on `.status` or pull values out of `.payload`.
- **Bump *after* upload** — if `upload` fails, the version files are never touched, so there is nothing to roll back. See "Version bump ordering and recovery" in `docs/configuration-reference.md`.
- **`--follow-tags`** — pushes the commit and its annotated tag in one round trip.

### Preview without side effects

Add `--dry-run` to any step to see what it would do without building, uploading, or writing version files:

```bash
shipit run release --dry-run --output json      # full step list, no execution
shipit version --bump patch --dry-run --output json   # computed before/after, nothing written
```

Direct action dry-runs also honor `--output json` and emit one `ActionResultEnvelope` with
`status: "dry_run"`. For `coverage` and `test-results`, do not combine `--output json` with a
non-JSON `--format`; omit `--format` or set it to `json`.

## Linux Swift Version

The Linux CI job uses `swift:6.3.1-noble` (Ubuntu 24.04, current stable Swift). To update it, change the `container.image` value in `.github/workflows/ci.yml` and the `SWIFT_IMAGE` variable at the top of the `Makefile`.

## Cross-platform build systems on CI

When `build_system` resolves to anything other than `native`, ShipItSwifty layers a pre-build step on top of the regular pipeline. Each build system needs its own toolchain on the runner.

### Kotlin Multiplatform

Both iOS and Android KMP builds run from macOS runners — the iOS path links the shared framework via Gradle before invoking `xcodebuild`, and you can't run `xcodebuild` from a Linux runner.

GitHub Actions example:

```yaml
jobs:
  ios-beta:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - uses: gradle/actions/setup-gradle@v3
      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ hashFiles('**/*.gradle.kts', 'gradle.properties') }}
      - run: shipit doctor --ci
      - run: shipit run beta-ios --ci --output json
        env:
          ASC_KEY_ID:    ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}

  android-beta:
    runs-on: macos-15           # or ubuntu-latest — Android-only KMP target works on Linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 17 }
      - uses: gradle/actions/setup-gradle@v3
      - run: shipit run beta-android --ci --output json
        env:
          GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}
```

Things to watch on KMP CI:

- **JDK 17+ is required** — Kotlin 1.9 / Compose Multiplatform target JDK 17 by default.
- **Gradle cache is essential** — the first link of `Shared.framework` is slow; subsequent invocations are nearly free if `~/.gradle` is cached.
- **`shipit doctor` validates** that `java` is on PATH and `./gradlew` is executable. Run it as the first step so a missing toolchain fails fast.
- **iOS simulators**: `xcodebuild build` may need a destination. On macOS runners, the bundled simulators are pre-installed; pin the OS version via `--destination` if reproducibility matters.

### Flutter and React Native

Flutter workflows need the Flutter SDK before running ShipItSwifty. React Native workflows need Node and the project package manager (`npm`, `yarn`, or `pnpm`).

```yaml
jobs:
  flutter-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: shipit run beta-android --ci --output json

  react-native-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 17 }
      - run: npm ci
      - run: shipit run beta-android --ci --output json
```

Use macOS runners for Flutter iOS or React Native iOS distribution because both require Xcode and Apple signing tooling.

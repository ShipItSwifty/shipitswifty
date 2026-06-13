# ShipItSwifty Walkthrough

> **DocC mirror:** This walkthrough is also available as an interactive tutorial in DocC — see chapter 1 ("iOS Quick Start") of the `ShipItKit` tutorials. Build with `swift package generate-documentation --target ShipItKit`.

A step-by-step guide to setting up and running your first release.

## Prerequisites

- macOS 15+, Swift 6 / Xcode 16+
- An Apple Developer account
- (For ASC features) An App Store Connect API key

## Step 1 — Clone and build

```bash
git clone https://github.com/shipitswifty/shipitswifty
cd ShipItSwifty
swift build
```

## Step 2 — Create your config file

Use `generate` as the default setup path. It walks you through the missing project details, auto-detects what it can from Xcode, and writes `Shipfile.yml` for you.

```bash
shipit generate
```

If you already know the release goal, target it explicitly:

```bash
shipit generate --goal beta
```

For non-interactive use (CI/agent flows):

```bash
shipit generate --goal beta --non-interactive
```

The generated result includes:
- `appConfig` — every inferred value with `source`, `confidence`, and `why`
- `missing` — required fields that couldn't be resolved, with env var names
- `ambiguities` — fields where multiple candidates exist and confirmation is needed
- `readiness` — blockers, missing secrets, and signing risk level
- `nextAction.command` — the exact command to run next
- `shipfilePath` — where the generated config was written

If your project is ambiguous (e.g., multiple runnable schemes), resolve those first, then re-run to get the `create_shipfile` action.

If you want to hand the project off to an agent after generation, `ai-session` is still available as a secondary, agent-focused command:

```bash
shipit ai-session --goal beta --output json
```

Manual setup is still available if you prefer to start from the example file:

```bash
cp Shipfile.example.yml Shipfile.yml
```

`Shipfile.yml` is only the default filename. You can rename it and pass `--shipfile <path>` on every command.

Config-backed commands require the file to exist. If you rename the file, pass the same `--shipfile <path>` on `env`, `doctor`, `run`, and any action command.

Edit your config file to match your project:

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  bundle_id: com.example.myapp
  team_id: ABCDE12345
```

## Step 3 — Set App Store Connect credentials

For actions that call the App Store Connect API, you need `ASC_KEY_ID`, `ASC_ISSUER_ID`, and exactly one of `ASC_PRIVATE_KEY` or `ASC_PRIVATE_KEY_PATH`.

`ASC_ISSUER_ID` is shown on the App Store Connect API Keys page. It is not stored in the `.p8` file.

If you only plan to use local build flows such as `build`, `test`, `archive`, or `export`, you can skip this step.

Need help locating these values? See [Credential Lookup](credential-lookup.md).

Where the Apple values come from:

| Value | Where to find it |
|---|---|
| `team_id` | Usually auto-detected by `shipit generate` from Xcode signing settings. If you need to set it manually, use the 10-character Apple Developer Team ID shown in the Apple Developer account or in Certificates, IDs & Profiles for the selected team. |
| `ASC_KEY_ID` | App Store Connect -> `Users and Access` -> `Integrations` -> `App Store Connect API` -> API key `Key ID` |
| `ASC_ISSUER_ID` | Same App Store Connect API page. This is account-level metadata, not part of the downloaded `.p8` file. |
| `ASC_PRIVATE_KEY_PATH` | Local filesystem path to the `.p8` file you downloaded when creating the API key |
| `ASC_PRIVATE_KEY` | Raw contents of that same `.p8` file, typically stored directly in CI secrets |

If `team_id` is missing and you are unsure which one to use, open your Xcode project Signing settings and use the team selected for the app target. That should match the Team ID ShipIt needs.

Find the values in App Store Connect:
1. Open `App Store Connect`.
2. Go to `Users and Access`.
3. Open `Integrations`.
4. Open `App Store Connect API`.
5. Create or select an API key.
6. Copy `Key ID` into `ASC_KEY_ID`.
7. Copy `Issuer ID` into `ASC_ISSUER_ID`.
8. Download the `.p8` file.

For local development, point at a `.p8` file:

```yaml
app_store_connect:
  key_id: ${ASC_KEY_ID}
  issuer_id: ${ASC_ISSUER_ID}
  key_path: ./.secrets/AuthKey_XXXXXXXXXX.p8
```

Export the variables in your shell:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY_PATH=./.secrets/AuthKey_XXXXXXXXXX.p8
```

For CI, set `ASC_PRIVATE_KEY` to the raw `.p8` file contents instead of using a file path. Do not set both private key forms unless you intentionally want `ASC_PRIVATE_KEY` to win.

You only need ASC credentials for commands that talk to Apple services, such as `upload`, `testflight`, `metadata`, and `provision`.

## Step 4 — Verify resolved configuration

```bash
swift run shipit env
```

This prints all resolved values — workspace, scheme, credentials, etc. — so you can confirm everything is wired up before running any actions.

It also prints the selected shipfile path, processed files, and the relevant environment variables that were read during resolution.

If you used a custom filename, run `swift run shipit env --shipfile ./path/to/your-config.yml`.

## Step 5 — Run individual commands

```bash
# Compile
swift run shipit build

# Discover available test destinations (simulators and devices)
xcodebuild -showdestinations -scheme MyApp -workspace MyApp.xcworkspace

# Run tests on a specific destination
swift run shipit test

# Archive for App Store
swift run shipit archive

# Export IPA
swift run shipit export

# Push to TestFlight
swift run shipit testflight
```

> **Test destinations:** `shipit test` supports automatic destination discovery — when no `destinations` list is configured in `Shipfile.yml` (and no `--destination` flag is passed), it queries available simulators and selects an appropriate one automatically. You can still override with an explicit list or `xcodebuild -showdestinations` to find valid destination strings for your scheme.

## Step 6 — Define workflows for repeatable releases

ShipItSwifty uses Apple's two-version model:

| Plist key | Format | Role |
|---|---|---|
| `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH` | User-facing marketing version. Bump manually for releases. |
| `CFBundleVersion` | plain integer | Internal build counter. Auto-incremented on every beta run. |

Add workflows to `Shipfile.yml`. The `version` step with `bump: build` increments only `CFBundleVersion` and leaves `CFBundleShortVersionString` untouched — the correct behavior for beta runs.

**Local-only beta** (no upload to App Store Connect):

```yaml
versioning:
  strategy: sequential   # keeps CFBundleVersion as a plain integer
  source: xcodeproj

workflows:
  beta:
    - action: version
      options: { bump: build }   # bumps CFBundleVersion only
    - action: archive
    - action: export             # exports .ipa locally; no ASC credentials needed
```

**Local workflow with tests** (run before archive):

```yaml
versioning:
  strategy: sequential
  source: xcodeproj

workflows:
  local:
    - action: test
      options:
        destinations:
          - "platform=iOS Simulator,id=<simulator-udid>"
          # Run `xcodebuild -showdestinations -scheme MyApp` to get valid destination strings.
          # Multiple destinations are supported — one xcodebuild test pass per destination.
    - action: archive
    - action: export
```

**Beta with TestFlight upload** (requires `app_store_connect` credentials):

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
      options: { configuration: Release, export_method: app-store }
    - action: export
    - action: testflight
      options:
        groups: ["Internal QA"]
        changelog: "Bug fixes and improvements"
```

**Release** (bumps marketing version, submits for review):

```yaml
workflows:
  release:
    - action: version
      options: { bump: patch }   # bumps CFBundleShortVersionString patch segment
    - action: archive
    - action: export
    - action: upload
      options: { submit_for_review: true, phased_release: true }
```

Then run a workflow:

```bash
swift run shipit run beta
swift run shipit run release --ci
```

## Migrating from fastlane

If you already have a `Fastfile`, the easiest migration path is to translate each lane into a `Shipfile.yml` workflow and move shared config into the top-level sections.

### Concept mapping

| fastlane | ShipItSwifty |
|---|---|
| `Appfile` | `app:` + `app_store_connect:` in `Shipfile.yml` |
| `Fastfile` lane | `workflows:` entry |
| lane parameters / env vars | workflow `options:` + `SHIPIT_*` env vars |
| `match` | `shipit sign sync` |
| `gym` | `shipit archive` + `shipit export` |
| `scan` | `shipit test` |
| `pilot` | `shipit testflight` |
| `deliver` | `shipit metadata` and `shipit upload` |
| `increment_build_number` / `increment_version_number` | `shipit version` |

### Typical migration steps

1. Move app identity from `Appfile` into `Shipfile.yml`:

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  bundle_id: com.example.myapp
  team_id: ABCDE12345

app_store_connect:
  key_id: ${ASC_KEY_ID}
  issuer_id: ${ASC_ISSUER_ID}
  key_path: ./.secrets/AuthKey_XXXXXXXXXX.p8
```

2. Convert each lane into a workflow. For example, this fastlane lane:

```ruby
lane :beta do
  increment_build_number
  build_app
  upload_to_testflight(groups: ["Internal QA"])
end
```

becomes (with TestFlight upload):

```yaml
workflows:
  beta:
    - action: version
      options: { bump: build }
    - action: archive
      options: { configuration: Release, export_method: app-store }
    - action: export
    - action: testflight
      options:
        groups: ["Internal QA"]
```

Or, for a local-only beta that skips the App Store Connect upload:

```yaml
versioning:
  strategy: sequential   # ensures CFBundleVersion stays a plain integer
  source: xcodeproj      # reads/writes directly in .xcodeproj

workflows:
  beta:
    - action: version
      options: { bump: build }   # bumps CFBundleVersion only; marketing version unchanged
    - action: archive
    - action: export             # exports .ipa locally; no ASC credentials needed
```

3. Move secrets out of Ruby config and into environment variables:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY="$(cat ./.secrets/AuthKey_XXXXXXXXXX.p8)"
```

4. Replace lane invocations with `shipit` commands:

```bash
# fastlane beta
swift run shipit run beta

# fastlane test
swift run shipit test

# fastlane deliver
swift run shipit metadata
swift run shipit upload
```

5. Validate the migration before using it in CI:

```bash
# Human-readable check
shipit env
shipit run beta --dry-run

# Machine-readable check (agents/CI)
shipit generate --goal beta --non-interactive
shipit run beta --dry-run --output json
```

If you renamed the file, include `--shipfile ./path/to/your-config.yml` on both commands.

### Migration advice

- Start by migrating one lane, usually your beta/TestFlight flow, before moving release automation.
- Keep workflows small and explicit. ShipItSwifty favors separate `archive`, `export`, `testflight`, and `upload` steps over one large command.
- If your fastlane setup uses `match`, migrate signing separately and verify `shipit sign sync` before wiring it into a full release workflow.
- CI usually gets simpler: keep credentials in standard env vars and call `swift run shipit run <workflow> --ci --output json`.

## Dry Run Mode

Preview what a command or workflow would do without executing anything:

```bash
swift run shipit run release --dry-run
```

For structured output that agents and CI scripts can parse, combine with `--output json`:

```bash
swift run shipit run release --dry-run --output json
```

This returns the full step list with options, not mixed human text:

```json
{
  "action": "run",
  "status": "dry_run",
  "payload": {
    "workflow": "release",
    "mode": "dry_run",
    "stepCount": 4,
    "steps": [
      { "index": 1, "action": "version", "options": { "bump": "build" } },
      { "index": 2, "action": "archive", "options": null },
      { "index": 3, "action": "export", "options": null },
      { "index": 4, "action": "upload", "options": { "submit_for_review": true } }
    ]
  }
}
```

If you want colored human output in screenshots, demos, or piped logs, force it explicitly:

```bash
swift run shipit run release --dry-run --color always
swift run shipit doctor --no-color
```

## JSON Output

For CI pipelines and downstream tooling, use `--output json`:

```bash
swift run shipit build --scheme MyApp --output json | jq .
```

Color flags only affect human output. JSON output is always plain machine-readable text.

## Debugging

Enable verbose logging:

```bash
swift run shipit build --verbose
```

Run the doctor to diagnose environment issues:

```bash
swift run shipit doctor
```

If your config is not named `Shipfile.yml`, pass it explicitly:

```bash
swift run shipit doctor --shipfile ./path/to/your-config.yml
```

## Environment Variable Management

ShipIt auto-loads a `.env` file from the same directory as your `Shipfile.yml` before running any action. Process environment variables always take precedence — `.env` only fills in gaps.

### Creating a `.env` file

`shipit generate` offers to create one for you during Android signing setup. It writes `${VAR_NAME}` references for values already set in your environment:

```bash
# .env (generated by shipit generate)
SHIPIT_ANDROID__KEYSTORE_PATH="/path/to/release.keystore"
SHIPIT_ANDROID__KEY_ALIAS="release"
SHIPIT_ANDROID__KEYSTORE_PASSWORD="${SHIPIT_ANDROID__KEYSTORE_PASSWORD}"
SHIPIT_ANDROID__KEY_PASSWORD="${SHIPIT_ANDROID__KEY_PASSWORD}"
```

This keeps secrets out of the file — they resolve from your shell exports at runtime.

### Resolution priority

```
CLI flags > SHIPIT_* env vars > .env file > Shipfile.yml > built-in defaults
```

`Shipfile.yml` supports `${ENV_VAR}` expansion. `.env` expansion (`${VAR}` inside `.env` values) resolves from the process environment at load time.

## Validation

Validate your config and artifacts before deploying:

```bash
# Validate Shipfile structure and workflow semantics
swift run shipit validate yml

# Validate App Store metadata (text length, forbidden words, URLs)
swift run shipit validate metadata

# Validate an xcarchive or IPA before upload
swift run shipit validate archive --archive-path ./build/MyApp.xcarchive

# Validate an Android AAB/APK bundle
swift run shipit validate bundle --bundle ./build/app-release.aab

# Run all validation stages
swift run shipit validate all
```

## Coverage Reporting

After running tests, use `shipit coverage` to read and summarize native coverage artifacts:

```bash
# Auto-discover and summarize (first-party only by default)
swift run shipit coverage

# Per-target breakdown
swift run shipit coverage --first-party-only --targets

# Per-file breakdown
swift run shipit coverage --files

# Machine-readable for CI
swift run shipit coverage --format json

# PR comment / CI summary
swift run shipit coverage --format markdown

# Android (JaCoCo)
swift run shipit coverage --platform android
```

## Custom Actions

Define reusable, parameterized step sequences in `Shipfile.yml`:

```yaml
custom_actions:
  build_and_sign:
    description: "Test, archive, and export with a chosen method."
    parameters:
      method:
        type: string
        required: true
    steps:
      - action: test
      - action: archive
      - action: export
        options:
          method: "{{param.method}}"

workflows:
  beta:
    - action: build_and_sign
      options: { method: app-store }
    - action: testflight
```

`{{param.NAME}}` substitution is deliberately different from `${ENV_VAR}` expansion, GitHub Actions `${{ }}`, and CircleCI `<< >>` to avoid collisions. Composites can call other composites (acyclic).

## Cross-Platform Build Systems

ShipIt supports four build systems across iOS and Android:

| Build system | Set with | Detection rule |
|---|---|---|
| `native` (default) | `ios.build_system: native` | Default when no framework detected |
| `flutter` | `ios.build_system: flutter` | `pubspec.yaml` with `flutter:` key |
| `react_native` | `ios.build_system: react_native` | `package.json` with `react-native` dep |
| `kmp` | `ios.build_system: kmp` | `kotlin("multiplatform")` in `build.gradle.kts` |

See [`docs/kmp-quickstart.md`](kmp-quickstart.md) for KMP and [`docs/features.md`](features.md#cross-platform-build-systems) for the full matrix.

## Linux and Docker

Android workflows run on Linux. Use the provided Makefile for local Docker development:

```bash
make build-linux         # build via volume mount
make test-linux          # run Linux-compatible tests
make test-linux-coverage # tests + coverage
make shell-linux         # interactive container shell
```

Or build a local image with cached SPM dependencies:

```bash
make docker-build
make docker-test
```

## Version Bump Ordering and Recovery

### Recommended workflow order

Place the `version` step **after** `test` and `build` succeed, and pair it with a `git` commit step immediately after. This means:

- If `test` or `build` fails, the version files are never touched.
- If the version bump itself fails, nothing was written.
- If a later step (e.g. `export` or `testflight`) fails, the bumped version is already committed to git — recovery is a plain `git revert`.

> The `git` action with `operation: commit` stages **every** change in the working tree (`git add -A`) before committing — there is no per-file option. In CI this is usually what you want, since the runner starts from a clean checkout and the only modified files are the version bump. If you have unrelated local changes, commit or stash them first.

```yaml
workflows:
  beta:
    - action: test
    - action: archive
    - action: version
      options: { bump: build }
    - action: git
      options:
        operation: commit
        commit_message: "chore: bump build number [skip ci]"
    - action: export
    - action: testflight
```

Contrast this with bumping first (which leaves a committed version if a later step fails):

```yaml
# Avoid: version first means a failed archive leaves a stranded bump
workflows:
  beta:
    - action: version   # ← written to disk before anything else
    - action: archive   # ← if this fails, version is stuck at n+1
```

### Recovering a stranded version bump with git

If a workflow failed after bumping the version but before the git commit step, recover with:

```bash
# Preview what changed
git diff

# Restore version files to the last commit
git restore MyApp.xcodeproj/project.pbxproj
# or for project_spec / KMP sources:
git restore project.yml
git restore gradle.properties
```

### Previewing a version bump without writing

Use `--dry-run` with `shipit version` to see the computed before/after values without modifying any files:

```bash
# Human-readable preview
swift run shipit version --bump build --dry-run

# Machine-readable preview (for CI scripts or agents)
swift run shipit version --bump patch --dry-run --output json
```

Example human output:
```
DRY RUN: Would bump build (source: xcodeproj)
  build number: 42 → 43
```

Example JSON output:
```json
{
  "action": "version",
  "status": "dry_run",
  "payload": {
    "bump": "build",
    "source": "xcodeproj",
    "currentVersion": "1.0.0",
    "currentBuildNumber": "42",
    "newVersion": "1.0.0",
    "newBuildNumber": "43"
  }
}
```

## Common Caveats

- The package depends on the remote `SwiftyShell` Swift package, so your environment must be able to fetch Swift package dependencies.
- Full code-signing (`sign`, `provision`) flows require proper vault configuration (`VAULT_PASSWORD` and a cert repo).
- Some advanced ASC features are still under active development.

# ShipItSwifty

Swift-native CLI for **iOS and Android** app release automation, built end-to-end in Swift 6.

[![CI](https://github.com/shipitswifty/shipitswifty/actions/workflows/ci.yml/badge.svg)](https://github.com/shipitswifty/shipitswifty/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)

> **Documentation:** browse the [`docs/`](docs/) folder for guides and configuration reference, or build the DocC archive locally (see [Documentation](#documentation) below).

---

## What is it?

ShipItSwifty automates the build → archive → distribute pipeline for mobile apps, on both Apple and Android platforms, from a single declarative `Shipfile.yml`. It is delivered as:

- **`ShipItKit`** — a reusable Swift library where all the domain logic lives.
- **`shipit`** — a thin CLI on top of `ShipItKit` you can run locally or in CI.

Use the CLI directly, embed the library in your own Swift tools, or extend it with statically-linked plugins.

## Why?

| If you currently use… | ShipItSwifty offers |
|---|---|
| **fastlane** | A Swift-native, type-safe equivalent — no Ruby toolchain, structured JSON output, first-class Android support, and an AI-friendly schema for agent-driven release workflows. |
| **bash + xcodebuild + altool** | A typed `xcodebuild` wrapper, App Store Connect REST client, code-signing vault, and reusable workflows — without re-inventing them per repo. |
| **Bitrise / Codemagic steps** | A portable runner that does the same work locally and on any CI, with deterministic dry-runs and machine-readable output. |

## Features

| Area | iOS | Android | Notes |
|---|:-:|:-:|---|
| Build | ✅ | ✅ | `xcodebuild build` / `gradlew assemble<Variant>` |
| Test (unit + UI) | ✅ | ✅ | Multi-destination matrix on iOS, unit + instrumented on Android |
| Code coverage | ✅ | ✅ | Reads `.xcresult` / JaCoCo XML; first-party filtering, per-target/file breakdown, JSON & Markdown output |
| Lint / static analysis | ✅ | ✅ | `xcodebuild analyze` / `gradlew lint` |
| Archive | ✅ | ✅ | `.xcarchive` / `.aab` |
| Export | ✅ | — | `xcodebuild -exportArchive` with auto-generated export options |
| Code signing | ✅ | — | Vault-style sync from a Git-backed encrypted store |
| Provisioning | ✅ | — | Profile + App ID + device management via ASC API |
| App Store / TestFlight upload | ✅ | — | Native ASC REST client (no `altool` / `iTMSTransporter` dependency) |
| Google Play upload | — | ✅ | Service-account JWT auth, configurable track |
| Metadata push / pull | ✅ | — | Localized strings, release notes |
| Submission validation | ✅ | ✅ | `validate yml` / `validate metadata` / `validate archive` / `validate bundle` |
| Versioning | ✅ | ✅ | `agvtool`, project-spec (XcodeGen), or App Store Connect as source of truth |
| Screenshots | ✅ | — | Capture + frame; `frameit` integration |
| Notifications | ✅ | ✅ | Slack, generic webhooks, macOS notifications |
| Project generation | ✅ | — | Auto-runs XcodeGen / Tuist before Xcode-dependent steps |
| Workflow composition | ✅ | ✅ | Reusable parameterised `custom_actions` in YAML |
| Plugins | ✅ | ✅ | Statically-linked Swift packages contributing custom actions |
| AI-assisted setup | ✅ | ✅ | `ai-session` returns a stable JSON contract for agents (config inference, secrets, next-action, schema) |

For the full feature catalogue and roadmap, see [`docs/features.md`](docs/features.md).

## Requirements

- **iOS workflows (build, archive, sign, TestFlight, App Store Connect, etc.)**: macOS 15+ with Xcode 16+
- **Android workflows (build, test, archive, lint, Play Store)**: macOS 15+ **or** Linux (Swift 6.0+) with JDK 17+ and a project containing `gradlew`
- Swift 6 / Xcode 16+ (or the matching open-source Swift 6 toolchain on Linux)

> iOS-only commands (`sign`, `testflight`, `upload`, `metadata`, `precheck`, `provision`, `frame`, `snapshot`, `version`, `validate archive`, etc.) are unavailable on Linux because they depend on Apple-only toolchains (`xcodebuild`, `xcrun`, the Security framework, App Store Connect upload). Android workflows and the cross-platform commands (`build`, `test`, `archive`, `lint`, `coverage`, `play-store`, `validate yml`, `validate bundle`, `notify`, `run`, `inspect`, `generate`, `ai-session`) work on both macOS and Linux.

## Installation

### Build from source (recommended today)

```bash
git clone https://github.com/shipitswifty/shipitswifty
cd shipitswifty
swift build -c release
cp .build/release/shipit /usr/local/bin/shipit
```

### Homebrew

A formula template lives at [`Formula/shipit.rb`](Formula/shipit.rb), but there is **no published tap** at the time of writing. To install via Homebrew today you need to copy the formula into your own tap and install it as `--HEAD`:

```bash
brew tap-new <you>/shipit
cp Formula/shipit.rb "$(brew --repository)/Library/Taps/<you>/homebrew-shipit/Formula/shipit.rb"
brew install --HEAD <you>/shipit/shipit
```

The full checklist for publishing a tap, computing tarball SHAs, and cutting a stable release lives in [`docs/homebrew.md`](docs/homebrew.md).

## Quick start

```bash
# 1. Generate a Shipfile interactively
shipit generate

# 2. Diagnose your environment
shipit doctor

# 3. Run a single action
shipit build --scheme MyApp
shipit test --scheme MyApp

# 4. Or run a workflow defined in Shipfile.yml
shipit run beta
```

A minimal iOS `Shipfile.yml`:

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  # bundle_id / team_id are auto-detected from Xcode if omitted

app_store_connect:
  key_id: ${ASC_KEY_ID}
  issuer_id: ${ASC_ISSUER_ID}
  key_path: ./.secrets/AuthKey_XXXXXXXXXX.p8

code_signing:
  type: automatic

workflows:
  beta:
    - action: archive
      options: { export_method: app-store }
    - action: testflight
      options: { groups: ["Internal QA"] }
  release:
    - action: archive
    - action: export
    - action: upload
      options: { submit_for_review: true, phased_release: true }
```

A minimal Android `Shipfile.yml`:

```yaml
platform: android

android:
  module: app
  build_variant: release
  package_name: com.example.myapp
  play_track: internal

workflows:
  beta:
    - action: test
    - action: archive
    - action: play-store
```

Copy the full annotated example: `cp Shipfile.example.yml Shipfile.yml`.

## CLI reference (summary)

`shipit help <subcommand>` shows the full option list for every command.

| Group | Commands |
|---|---|
| **Setup / inspection** | `generate`, `doctor`, `env`, `inspect`, `suggest-config`, `schema` |
| **AI agents** | `ai-bootstrap`, `ai-session` |
| **Validation** | `validate yml`, `validate metadata`, `validate archive`, `validate bundle`, `validate all`, `precheck` (alias) |
| **Build & test** | `build`, `test`, `coverage`, `lint`, `archive`, `export` |
| **Distribution (iOS)** | `upload`, `testflight`, `metadata`, `sign`, `provision`, `snapshot`, `frame` |
| **Distribution (Android)** | `play-store` |
| **Versioning & ops** | `version`, `notify`, `run` |

Every command supports the same global options:

| Flag | Description |
|---|---|
| `--shipfile <path>` | Path to config file (default `./Shipfile.yml`; must exist for config-backed commands) |
| `--platform ios\|android` | Override platform auto-detection |
| `--output human\|json` | Output format (JSON is never colorized) |
| `--color auto\|always\|never` / `--no-color` | Color control for human output |
| `--verbose` | Enable debug logging |
| `--ci` | Non-interactive, strict-error CI mode |
| `--dry-run` | Preview without executing |

## Credentials

### App Store Connect (iOS)

For any action that calls the App Store Connect API:

| Variable | Purpose |
|---|---|
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY` | Raw `.p8` contents (preferred for CI) |
| `ASC_PRIVATE_KEY_PATH` | Path to the `.p8` file (preferred locally) |

You only need these for upload/metadata/precheck/provision flows. Local `build` / `test` / `archive` / `export` work without them.

### Google Play (Android)

| Variable | Purpose |
|---|---|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Raw service-account JSON (preferred for CI) |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` | Path to the JSON file (preferred locally) |

## Output modes

```bash
shipit build --scheme MyApp --output json | jq .
shipit run beta --dry-run --output json     # see the planned step list
```

JSON output is stable, machine-readable, and never colorized — suitable for CI dashboards, AI agents, or downstream tooling. Configuration failures emit a JSON failure envelope with a non-zero exit code.

## Architecture

```
Shipfile.yml / CLI flags / env vars
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient, GooglePlayClient?, platform)
        ↓
  ActionRegistry (actor) — built-in + plugin actions, by name
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope (Codable)
```

Hard rules enforced throughout the codebase:

1. All shell execution goes through **SwiftyShell** — never `Foundation.Process` directly.
2. All App Store Connect calls go through **`AppStoreConnectClient`** — no raw HTTP.
3. All public types are **`Sendable`** (Swift 6 strict concurrency).
4. Async work uses **structured concurrency** only.
5. Actions derive behaviour solely from their typed `Options` and the `ActionContext` — no hidden global state.

Detailed architecture, including the typed `XcodeBuild` and `Gradle` fluent wrappers used by every shell-driven action, is in [`docs/architecture.md`](docs/architecture.md).

## Extending with plugins

Plugins are statically-linked Swift packages that register custom `Action`s at startup. The full guide — including a runnable `BuildTimingAction` (wraps another action and records duration) and `CopyArtifactsAction` (copies built `.ipa` / `.aab` / dSYMs to a versioned folder) — lives in [`docs/plugin-development.md`](docs/plugin-development.md).

Skeleton:

```swift
import ShipItKit

public struct MyAction: Action {
    public static let name = "my-action"
    public static let description = "Does something useful"

    public struct Options: Codable, Sendable { public var foo: String? }
    public struct Result: Codable, Sendable { public var bar: String }

    public init() {}

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        context.logger.info("Running my-action with foo=\(options.foo ?? "nil")")
        return Result(bar: "done")
    }
}

public struct MyPlugin: ShipItPlugin {
    public static let name = "my-plugin"
    public static let description = "Custom release actions"
    public static let actions: [ActionDescriptor] = [
        MyAction.descriptor(for: MyAction())
    ]
}
```

## Documentation

ShipItSwifty's canonical docs are built with **DocC**. Browse them locally:

```bash
swift package generate-documentation --target ShipItKit
open .build/plugins/Swift-DocC/outputs/ShipItKit.doccarchive
```

The DocC archive includes a multi-chapter **interactive tutorial** (iOS quick start, Android quick start, and "build your first plugin"), 16 topic articles, and the full symbol-level API reference.

### Articles & guides

| Topic | DocC article | Long-form (mirrored) |
|---|---|---|
| **Getting started** | `GettingStarted` | — |
| **Walkthrough** | (see Tutorials chapter 1) | [`docs/walkthrough.md`](docs/walkthrough.md) |
| **Core concepts** | `CoreConcepts`, `Architecture` | [`docs/architecture.md`](docs/architecture.md) |
| **Configuration reference** | `ConfigurationReference` | [`docs/configuration-reference.md`](docs/configuration-reference.md) |
| **Workflows & composites** | `Workflows`, `CompositeActions` | — |
| **Actions catalog** | `ActionsCatalog` | [`docs/features.md`](docs/features.md) |
| **Versioning** | `Versioning` | — |
| **Coverage** | `Coverage` | — |
| **Validation** | `Validation` | — |
| **Code signing & vault** | `CodeSigningAndVault` | — |
| **App Store Connect** | `AppStoreConnectIntegration` | — |
| **Android & Google Play** | `AndroidAndGooglePlay` | [`docs/android-quickstart.md`](docs/android-quickstart.md) |
| **CI integration** | `CIIntegration` | [`docs/ci-setup.md`](docs/ci-setup.md) |
| **AI session protocol** | `AISession` | — |
| **Output formats** | `OutputFormats` | — |
| **Testing with mocks** | `TestingWithMocks` | [`docs/testing.md`](docs/testing.md) |
| **Migrating from Fastlane** | `MigratingFromFastlane` | — |
| **Error handling** | `ErrorHandling` | — |
| **Writing plugins** | `WritingPlugins` (+ Tutorials chapter 3) | [`docs/plugin-development.md`](docs/plugin-development.md) |
| **Security** | (in `CodeSigningAndVault`) | [`docs/security.md`](docs/security.md) |
| **Homebrew install** | — | [`docs/homebrew.md`](docs/homebrew.md) |
| **DocC API reference** | Build with `swift package generate-documentation --target ShipItKit` |

## Development

```bash
swift build
swift test --enable-code-coverage
swift test --filter ShipItKitTests.BuildActionTests
swift run shipit --help
```

### Linux / Docker

The `GradleKit`, `ShipItKit` core, and `CLI` targets build and test on Linux. A `Dockerfile` and `Makefile` are included for local development without a native Swift toolchain:

```bash
# Build + test (direct volume mount — no docker build step)
make build-linux
make test-linux

# Interactive shell inside the container
make shell-linux

# Or build a local image with SPM deps cached as a layer, then test
make docker-build
make docker-test

# See all available targets
make help
```

macOS-only targets (`XcodeBuildKit`, `XcodeGenKit`, and `IntegrationTests`) are automatically skipped on Linux.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full contributor guide.

## License

MIT — see [`LICENSE`](LICENSE).

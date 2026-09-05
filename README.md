# ShipItSwifty

Swift-native CLI for iOS and Android app release automation — open-source, local-first, and offline-capable for local build operations.

[![CI](https://github.com/shipitswifty/shipitswifty/actions/workflows/ci.yml/badge.svg)](https://github.com/shipitswifty/shipitswifty/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)

**Your credentials, builds, and artifacts remain under your control.** ShipItSwifty runs on your device using native toolchains and has no telemetry of its own. Upload actions contact the store or distribution service you select, and optional upstream tools such as Google's preview AndroidCLI may have their own telemetry policies.

---

## What it does

ShipItSwifty automates the build → archive → distribute pipeline for iOS and Android apps from a single declarative `Shipfile.yml`. It ships as:

- **`ShipItKit`** — a reusable Swift library where all domain logic lives
- **`shipit`** — a thin CLI you run locally or in CI
- **Standalone tool libraries** — typed wrappers for Xcode, Gradle, XcodeGen, and Google's preview AndroidCLI

## Why open-source and local-first?

| Concern | How ShipItSwifty addresses it |
|---|---|
| **Privacy** | All builds run on your machine. No source code, signing certificates, or API keys are ever sent to a third-party cloud. |
| **Auditability** | 100% open-source Swift 6. Read, fork, and audit every step of the pipeline. |
| **No vendor lock-in** | Runs on any Mac or Linux box with Swift 6. No proprietary agents or paid tiers required. |
| **Offline-capable** | Build, test, archive, and export work entirely offline. Only upload steps reach the network — and only to App Store Connect or Google Play directly. |

## Requirements

- **iOS workflows** (build, archive, sign, TestFlight, etc.): macOS 15+ with Xcode 16+
- **Android workflows** (build, test, archive, lint, Play Store): macOS 15+ or Linux with JDK 17+ and a project containing `gradlew`
- Swift 6 / Xcode 16+ (or the open-source Swift 6 toolchain on Linux)

## Install

Install the latest stable release from the Homebrew tap:

```bash
brew tap shipitswifty/tap
brew install shipit
```

Until then, build from source:

```bash
git clone https://github.com/shipitswifty/shipitswifty
cd shipitswifty
swift build -c release
cp .build/release/shipit /usr/local/bin/shipit
```

## Quick start

```bash
# Generate a Shipfile interactively
shipit generate

# Check your environment
shipit doctor

# Run a single action
shipit build --scheme MyApp
shipit test --scheme MyApp

# Use Google's AndroidCLI directly (optional preview integration)
shipit android-cli emulator list
shipit android-cli skills list --long

# Run a workflow defined in Shipfile.yml
shipit run beta
```

AndroidCLI support is opt-in for workflows and complements the existing Gradle/ADB pipeline. Gradle remains the build, test, archive, and lint engine. See the [Android quickstart](docs/android-quickstart.md) and [configuration reference](docs/configuration-reference.md#androidcli-preview-opt-in).

## Documentation

| Guide | |
|---|---|
| [Walkthrough](docs/walkthrough.md) | Step-by-step getting started |
| [Configuration reference](docs/configuration-reference.md) | All Shipfile.yml keys and env vars |
| [Features & actions catalog](docs/features.md) | Full list of built-in actions |
| [Architecture](docs/architecture.md) | Layer diagram, core types, exit codes |
| [CI integration](docs/ci-setup.md) | GitHub Actions, GitLab CI, Bitrise |
| [Android quickstart](docs/android-quickstart.md) | Android-specific setup |
| [React Native quickstart](docs/react-native-quickstart.md) | React Native / Expo setup |
| [KMP quickstart](docs/kmp-quickstart.md) | Kotlin Multiplatform setup |
| [Plugin development](docs/plugin-development.md) | Writing custom actions |
| [Security](docs/security.md) | Secrets management, threat mitigations |
| [Credential lookup](docs/credential-lookup.md) | Finding your ASC / Play Store keys |
| [Testing](docs/testing.md) | Testing strategy and mocking |
| [Homebrew install](docs/homebrew.md) | Tap setup and stable release checklist |

DocC API reference: `swift package generate-documentation --target ShipItKit`

## Development

```bash
swift build
swift test --enable-code-coverage
swift test --filter ShipItKitTests.BuildActionTests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor guide. If navigating the codebase, start with [`docs/agent-index.md`](docs/agent-index.md).

## License

MIT — see [LICENSE](LICENSE).

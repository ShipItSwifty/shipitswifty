# ShipItSwifty

Swift-native CLI toolkit for iOS app release automation, built entirely in Swift 6.

[![CI](https://github.com/ArjangConsulting/ShipItSwifty/actions/workflows/ci.yml/badge.svg)](https://github.com/ArjangConsulting/ShipItSwifty/actions/workflows/ci.yml)

## What is it?

ShipItSwifty automates the iOS release pipeline:

- Build, test, archive, and export your app
- Distribute to TestFlight and the App Store
- Manage code signing via an encrypted certificate vault
- Capture and frame screenshots
- Bump versions and push metadata
- Post Slack notifications

It is structured as a **library** (`ShipItKit`) and a **CLI** (`shipit`), so you can use the command line directly or embed the library in your own Swift tools.

## Requirements

- macOS 15+
- Swift 6 / Xcode 16+

## Quick Start

```bash
# Build the CLI
swift build

# Create a config file
cp Shipfile.example.yml Shipfile.yml

# Verify your configuration
swift run shipit env

# Run a build
swift run shipit build --scheme MyApp

# Force colorful human output
swift run shipit build --scheme MyApp --color always

# Run a test suite
swift run shipit test --scheme MyApp

# Run a release workflow
swift run shipit run beta
```

## Installation

```bash
git clone https://github.com/maniramezan/ShipItSwifty
cd ShipItSwifty
swift build
```

To use `shipit` globally, copy the binary:

```bash
swift build -c release
cp .build/release/shipit /usr/local/bin/shipit
```

## Configuration

Create a config file at your project root. `Shipfile.yml` is the default name, but you can use any path with `--shipfile <path>`:

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  # bundle_id: com.example.myapp  # Optional; auto-detected from Xcode if omitted
  # team_id: ABCDE12345           # Optional; auto-detected from Xcode if omitted

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

Copy the full example: `cp Shipfile.example.yml Shipfile.yml`

You do not have to keep the name `Shipfile.yml`. ShipIt uses `./Shipfile.yml` by default, but any YAML file path works with `--shipfile <path>`.

All config-backed CLI commands require the file to exist. If `./Shipfile.yml` is missing, or if `--shipfile <path>` points to a missing file, the command exits non-zero with exit code `2`.

## CLI Commands

| Command | Description |
|---|---|
| `shipit init` | Scaffold a default `Shipfile.yml` interactively |
| `shipit build` | Compile with `xcodebuild build` |
| `shipit test` | Run tests with `xcodebuild test` |
| `shipit archive` | Archive for distribution |
| `shipit export` | Export IPA from archive |
| `shipit upload` | Upload IPA to App Store Connect |
| `shipit testflight` | Distribute to TestFlight |
| `shipit sign` | Install certificates and profiles |
| `shipit provision` | Sync provisioning profiles |
| `shipit snapshot` | Capture screenshots |
| `shipit frame` | Frame screenshots |
| `shipit version` | Bump version or build number |
| `shipit metadata` | Push App Store metadata |
| `shipit precheck` | Validate submission readiness |
| `shipit notify` | Send Slack notifications |
| `shipit run <workflow>` | Execute a named workflow from Shipfile |
| `shipit env` | Print resolved configuration, environment variables, and processed files |
| `shipit doctor` | Diagnose environment issues using the selected Shipfile |

### Global options (all commands)

| Flag | Description |
|---|---|
| `--shipfile <path>` | Path to config file. Defaults to `./Shipfile.yml`, and the file must exist for config-backed commands |
| `--output human\|json` | Output format (default: `human`) |
| `--color auto\|always\|never` | Color mode for human output (default: `auto`) |
| `--no-color` | Disable color in human output |
| `--verbose` | Enable debug logging |
| `--ci` | CI mode — non-interactive, strict errors |
| `--dry-run` | Preview without executing |

## Color Output

Human-readable output supports ANSI colors for headers, status lines, dry-run output, and tables.

```bash
swift run shipit build --scheme MyApp --color always
swift run shipit doctor --no-color
```

Use `--color auto` to follow terminal detection, `--color always` to force colors, and `--color never` or `--no-color` to disable them.

## App Store Connect Credentials

For actions that call the App Store Connect API, you need:
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- exactly one of `ASC_PRIVATE_KEY` or `ASC_PRIVATE_KEY_PATH`

`ASC_PRIVATE_KEY` is the raw contents of the downloaded `.p8` file. `ASC_PRIVATE_KEY_PATH` is a local file path alternative. If both are set, ShipIt prefers `ASC_PRIVATE_KEY`.

If you only use local Xcode flows such as `build`, `test`, `archive`, or `export`, you can skip App Store Connect credentials entirely.

Where to get them in App Store Connect:
1. Open `App Store Connect`.
2. Go to `Users and Access`.
3. Open the `Integrations` tab.
4. Open `App Store Connect API`.
5. Create or select an API key.
6. Copy the `Key ID` into `ASC_KEY_ID`.
7. Copy the `Issuer ID` into `ASC_ISSUER_ID`.
8. Download the `.p8` file and either:
   - store its contents in `ASC_PRIVATE_KEY`, or
   - point `ASC_PRIVATE_KEY_PATH` at the file locally.

| Variable | Description |
|---|---|
| `ASC_KEY_ID` | API key ID from App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID from App Store Connect |
| `ASC_PRIVATE_KEY` | Raw `.p8` key contents (preferred for CI) |
| `ASC_PRIVATE_KEY_PATH` | Path to `.p8` file (local development) |

## JSON Output

Every command supports `--output json` for machine-readable output, suitable for CI pipelines or downstream tooling:

```bash
swift run shipit build --scheme MyApp --output json | jq .
```

JSON output is never colorized.

If configuration loading fails, ShipIt returns a non-zero exit code and prints a failure envelope in JSON mode.

## Architecture

```
Shipfile.yml / CLI flags / env vars
        ↓
  ConfigResolver  →  ResolvedConfig
        ↓
  ActionContext (shell, logger, config, AppStoreConnectClient)
        ↓
  ActionRegistry (actor) — maps action names → ActionDescriptors
        ↓
  Workflow.run(context:registry:)  →  executes WorkflowStep[] sequentially
        ↓
  Action.run(with:context:)  →  ActionResultEnvelope
```

Two products:

- **`ShipItKit`** — reusable library; all domain logic
- **`shipit`** (CLI) — thin argument-parsing layer over `ShipItKit`

## Documentation

- [Walkthrough](docs/walkthrough.md) — step-by-step guide
- [CI Setup](docs/ci-setup.md) — GitHub Actions and CI configuration
- [Configuration Reference](docs/configuration-reference.md) — all Shipfile keys
- [Plugin Development](docs/plugin-development.md) — writing custom actions
- [DocC API Reference](https://maniramezan.github.io/ShipItSwifty/documentation/shipitkit/) — generated from source

## Development

```bash
# Build
swift build

# Run all tests with coverage
swift test --enable-code-coverage

# Run a single test suite
swift test --filter ShipItKitTests

# Run specific test
swift test --filter ShipItKitTests.JSONValueTests

# Run CLI directly
swift run shipit --help
```

## Extending with Plugins

Plugins are statically linked Swift packages that add custom actions. Implement `ShipItPlugin` and register at bootstrap:

```swift
public struct MyPlugin: ShipItPlugin {
    public static let name = "my-plugin"
    public static let description = "Custom release actions"
    public static var actions: [ActionDescriptor] = [
        MyCustomAction.descriptor(for: MyCustomAction())
    ]
}
```

See [Plugin Development](docs/plugin-development.md) for a full walkthrough.

## License

MIT

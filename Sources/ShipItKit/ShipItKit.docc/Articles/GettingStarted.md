# Getting Started

Add ShipItKit to your project and run your first release action.

## Overview

ShipItSwifty consists of five products:

- **`XcodeBuildKit`** — standalone typed wrappers for `xcodebuild`, `xcode-select`, and destination discovery
- **`GradleKit`** — standalone typed wrappers for Gradle, `adb`, `bundletool`, and Android emulator tooling
- **`XcodeGenKit`** — standalone typed wrappers for `xcodegen`
- **`ShipItKit`** — the reusable release automation library; it re-exports the standalone tool kits
- **`shipit`** — a CLI that wraps `ShipItKit` for use from the terminal and CI

This guide covers both paths.

## Prerequisites

- macOS 15+
- Swift 6 / Xcode 16+
- Access to the `SwiftyShell` Swift package dependency when building the package

## Using the CLI

### 1. Build and run

```bash
swift build
swift run shipit --help
```

### 2. Create a config file

Copy the example config and fill in your app's details:

```bash
cp Shipfile.example.yml Shipfile.yml
```

`Shipfile.yml` is only the default filename. You can rename it and pass `--shipfile <path>` when using the CLI.

Config-backed CLI commands require the selected file to exist. If you rename the file, pass the same `--shipfile <path>` everywhere you call `shipit`.

Edit your config file:

```yaml
app:
  workspace: MyApp.xcworkspace
  scheme: MyApp
  bundle_id: com.example.myapp
  team_id: ABCDE12345
```

### 3. Verify your configuration

```bash
swift run shipit env
```

This prints all resolved configuration values so you can confirm the right workspace, scheme, and credentials are picked up.

It also shows which files were processed and which relevant environment variables were read.

If you used a custom config filename, pass it with `--shipfile <path>`.

### 4. Run a build

```bash
swift run shipit build --scheme MyApp
```

### 5. Run a workflow

Define workflows in `Shipfile.yml`:

```yaml
workflows:
  beta:
    - action: archive
      options: { export_method: app-store }
    - action: testflight
      options: { groups: ["Internal QA"] }
```

Then execute:

```bash
swift run shipit run beta
```

## Using ShipItKit as a Library

Add the package to your `Package.swift`:

```swift
.package(path: "../ShipItSwifty"),
```

Then import and use:

```swift
import ShipItKit

let resolver = ConfigResolver()
let config = try await resolver.resolve(cliOptions: .init(), shipfilePath: "./Shipfile.yml")
let context = ActionContext(config: config, shell: MyShellContext(), logger: myLogger)

let result = try await BuildAction().run(
    with: BuildAction.Options(scheme: "MyApp"),
    context: context
)
```

## App Store Connect Credentials

Set these environment variables for any action that talks to the ASC API:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- exactly one of `ASC_PRIVATE_KEY` or `ASC_PRIVATE_KEY_PATH`

`ASC_ISSUER_ID` comes from the App Store Connect API Keys page. It is not embedded in the downloaded `.p8` file.

If you only use local Xcode actions such as `build`, `test`, `archive`, or `export`, you can skip these credentials.

Find these values in App Store Connect:
1. Open `Users and Access`.
2. Open `Integrations`.
3. Open `App Store Connect API`.
4. Create or select an API key.
5. Copy `Key ID` and `Issuer ID`.
6. Download the `.p8` file.

| Variable | Description |
|---|---|
| `ASC_KEY_ID` | API key identifier from App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID from App Store Connect |
| `ASC_PRIVATE_KEY` | Raw `.p8` key contents (preferred for CI) |
| `ASC_PRIVATE_KEY_PATH` | Path to `.p8` file (local development) |

## Next Steps

- Read <doc:CoreConcepts> to understand the action model
- See <doc:ConfigurationReference> for all Shipfile options
- See <doc:WritingPlugins> to extend ShipItKit with custom actions

# CI Setup

> **DocC mirror:** Also available as the `CIIntegration` article in the `ShipItKit` DocC archive.

How to run ShipItSwifty in GitHub Actions and other CI systems.

## GitHub Actions

The repository includes two pre-built workflows:

| Workflow | File | Trigger |
|---|---|---|
| Build & Test | `.github/workflows/ci.yml` | Push / PR to `main` |
| Build DocC | `.github/workflows/docc.yml` | Push to `main` + manual |

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
| `VAULT_PASSWORD` | Passphrase for encrypted certificate repo |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (optional) |
| `SHIPIT_TEST_P12_BASE64` | Base64-encoded development `.p12` for signing integration tests |
| `SHIPIT_TEST_P12_PASSWORD` | Export password for the `.p12` above |

`SHIPIT_TEST_P12_BASE64` and `SHIPIT_TEST_P12_PASSWORD` are only needed if you want the signing
integration tests to run in CI. Without them, those tests skip automatically.

To produce the base64 value from a `.p12` file:

```bash
base64 -i MyCert.p12 | pbcopy    # copies to clipboard — paste as the secret value
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
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v6
        with:
          path: ShipItSwifty

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.4.app

      - name: Run workflow
        working-directory: ShipItSwifty
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
          VAULT_PASSWORD: ${{ secrets.VAULT_PASSWORD }}
        run: swift run shipit run ${{ github.event.inputs.workflow }} --ci --output json
```

## Recommended Environment Variables

Set these for any CI job that uses ShipItSwifty:

```bash
ASC_KEY_ID=...
ASC_ISSUER_ID=...
ASC_PRIVATE_KEY=...      # raw .p8 contents
VAULT_PASSWORD=...       # for encrypted certificate vault
SLACK_WEBHOOK_URL=...    # optional
```

## Basic CI Steps

```bash
swift build
swift test --enable-code-coverage
swift run shipit doctor --ci
```

If your CI stores the config at a non-default path, pass it explicitly on every ShipIt command:

```bash
swift run shipit doctor --ci --shipfile ./config/Shipfile.ci.yml
swift run shipit run beta --ci --output json --shipfile ./config/Shipfile.ci.yml
```

## JSON Output in CI

Use `--output json` for machine-readable results:

```bash
swift run shipit build --scheme MyApp --output json | jq .status
```

## DocC GitHub Pages

The `docc.yml` workflow builds API documentation and deploys it to GitHub Pages automatically on every push to `main`.

Enable GitHub Pages in your repo settings:
1. Go to **Settings → Pages**
2. Set **Source** to **GitHub Actions**

The docs will be available at `https://<org>.github.io/ShipItSwifty/documentation/shipitkit/`.

## Xcode Version

The workflows pin `Xcode_26.4.app`. Update the `xcode-select` step if you need a different version. Available Xcode versions on GitHub's `macos-26` runner are listed in the [GitHub Actions runner images](https://github.com/actions/runner-images) documentation.

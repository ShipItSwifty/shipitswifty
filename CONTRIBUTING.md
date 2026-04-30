# Contributing to ShipItSwifty

Thanks for your interest in contributing! This project is an open-source Swift CLI for iOS and Android release automation, and contributions of all sizes are welcome.

## How to contribute

The flow is intentionally lightweight:

1. **File an issue first.** Open one describing the bug, the feature, or the question. This gives us a chance to align on scope before you invest time in code, and gives others visibility into what's being worked on.
2. **Fork and branch.** Branch from `main` with a short descriptive name (e.g. `fix/coverage-windows`, `feat/play-store-staged-rollout`).
3. **Make your changes.** Keep PRs focused — one concern per PR is easier to review and merge.
4. **Add or fix tests.**
   - New behavior → add a test.
   - Bug fix → add a regression test that fails without your change.
   - Refactor → make sure the existing tests still cover the affected code.
5. **Open a PR.** Reference the issue (`Fixes #123`). Describe what changed and why. Don't worry about polishing the description — we'll iterate on it together if needed.

That's it. CI will run build, tests, and DocC validation on every PR. If a check fails, push a fix to the same branch — no need to open a new PR.

## Building and testing

```bash
swift build
swift test                                  # unit + CLI tests
swift test --enable-code-coverage           # with coverage
swift test --filter ShipItKitTests          # one target
swift test --filter ShipItKitTests.BuildActionTests  # one suite
```

`swift test` runs **unit tests only** by default. Integration tests live in a separate target and skip cleanly without credentials — see [Integration tests](#integration-tests) below if you want to run them locally.

## Project conventions (light-touch)

A few things that keep the codebase consistent — not hard rules, but good defaults:

- **Swift 6 strict concurrency.** All public types are `Sendable`, all async work is structured. The compiler enforces most of this for you.
- **Shell execution goes through SwiftyShell**, not `Foundation.Process`.
- **App Store Connect calls go through `AppStoreConnectClient`**, not raw `URLSession`.
- **One `Action` per file** in `Sources/ShipItKit/Actions/`; one `Command` per file in `Sources/CLI/Commands/`.
- **Tests use Swift Testing** (`@Test`, `#expect`, `#require`) where possible.

When you add a new action or change an existing one, the [`AGENTS.md`](AGENTS.md) checklist lists the touchpoints (schema catalog, `docs/features.md`, AI session builder, etc.). It's there to keep the agent-facing surfaces in sync — skim it when relevant, ignore it when not.

## Integration tests

`Tests/IntegrationTests/` exercises real flows: `xcodebuild`, the App Store Connect API, the Google Play API, code-signing keychains. Tests that need credentials skip silently when the env vars are absent, so you can run the whole target without any setup:

```bash
swift build
swift test --filter IntegrationTests
```

If you want to run the credentialed tests:

```bash
cp .env.integration.example .env.integration
# Fill in the values you need (see sections below)
source .env.integration
swift build && swift test --filter IntegrationTests
```

All credentialed tests target a dedicated dummy app (`com.shipitswifty.integration`) that is never published, and assert this scope as their first line. Misconfigured environments cannot accidentally hit a production app.

### iOS / App Store Connect credentials

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
export ASC_PRIVATE_KEY="$(cat ~/path/to/AuthKey_XXXXXXXXXX.p8)"
# or:
export ASC_PRIVATE_KEY_PATH=~/path/to/AuthKey_XXXXXXXXXX.p8
```

Request access to the integration Apple Developer account from a maintainer — please don't use your personal or production account.

### Android / Google Play credentials

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=~/path/to/play-service-account.json
```

Request the `play-service-account.json` from a maintainer. The service account is scoped to the integration app only.

### Android SDK setup (for real Gradle builds)

```bash
export ANDROID_HOME=~/Library/Android/sdk
cd Tests/IntegrationTests/Fixtures/android-sample
gradle wrapper --gradle-version 8.7
cd -
```

Without this, Android build tests skip with a descriptive message.

### iOS Simulator setup (for `xcodebuild test`)

```bash
xcrun simctl boot "iPhone 16"
open -a Simulator
```

`xcodebuild build` and `xcodebuild archive` don't need a booted simulator.

### Signing credentials (for P12 round-trip tests)

The `.requiresP12Credentials` trait gates a CI signing round-trip test. You need a **development** `.p12` (not a distribution certificate). The test creates and destroys a temporary keychain — it never touches your login keychain.

```bash
export SHIPIT_TEST_P12_BASE64="$(base64 -i MyCert.p12)"
export SHIPIT_TEST_P12_PASSWORD=your-p12-export-password
swift build && swift test --filter IntegrationTests.SigningTests
```

GitHub Actions secrets only accept text, so the binary `.p12` is base64-encoded for transport and decoded back to a temp file at runtime.

## Adding a new integration test

1. Add it to the appropriate file in `Tests/IntegrationTests/`.
2. If it needs credentials, decorate with the relevant trait:
   - `.requiresASCCredentials`
   - `.requiresGooglePlayCredentials`
   - `.requiresAndroid`
   - `.requiresSimulator`
   - `.requiresSigningIdentity`
   - `.requiresP12Credentials`
3. Call `assertIntegrationScope(shipfile: ...)` before any credentialed API call.
4. Run `swift test --filter IntegrationTests` locally — verify it skips cleanly without credentials, then verify it passes with credentials sourced from `.env.integration`.

## Questions

Open an issue. We're happy to help.

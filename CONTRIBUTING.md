# Contributing to ShipItSwifty

## Building

```bash
swift build
swift test          # unit + CLI tests
```

## Test tiers

There are three test tiers with different requirements:

### Tier 1 — Unit tests (no setup needed)

```bash
swift test --filter ShipItKitTests
swift test --filter CLITests
```

No credentials, simulators, or SDKs required.

### Tier 2 — Integration tests (requires pre-built binary)

```bash
swift build                              # build shipit binary first
swift test --filter IntegrationTests     # credential tests auto-skip
```

This runs:
- Real `shipit` CLI invocations (schema, validate, dry-run paths)
- Real `xcodebuild build/archive` against `Tests/IntegrationTests/Fixtures/ios-sample/`
- Coverage parsing against a pre-recorded JaCoCo XML fixture
- Android dry-run paths (no SDK needed)

Tests requiring credentials silently skip when the env vars are absent.
The archive validation test archives the `ios-sample` fixture and validates the result inline.

### Tier 3 — Integration tests with credentials

Source your credential file then run the same command:

```bash
cp .env.integration.example .env.integration
# Fill in your values (see sections below)
source .env.integration
swift build && swift test --filter IntegrationTests
```

---

## iOS / App Store Connect credentials

All ASC integration tests target **`com.shipitswifty.integration`** — a dedicated dummy app
that is never published. Tests refuse to run against any other bundle ID.

1. Request access to the **integration Apple Developer account** from a maintainer.
   Do **not** use your personal or production developer account.
2. In App Store Connect → Users and Access → Integrations → Keys, create a key with **App Manager** role.
3. Set these environment variables:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
export ASC_PRIVATE_KEY="$(cat ~/path/to/AuthKey_XXXXXXXXXX.p8)"
# or:
export ASC_PRIVATE_KEY_PATH=~/path/to/AuthKey_XXXXXXXXXX.p8
```

---

## Android / Google Play credentials

All Google Play integration tests target **`com.shipitswifty.integration`** — a dedicated dummy
app on the internal track. The service account is **scoped to this single app** in Play Console;
it cannot reach any other app even if credentials leak.

1. Request the `play-service-account.json` file from a maintainer.
2. Set:

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=~/path/to/play-service-account.json
```

---

## Android SDK setup (for real Gradle builds)

Real Android builds require `ANDROID_HOME` and a bootstrapped `gradlew`:

```bash
# Install Android SDK (via Android Studio or command-line tools)
export ANDROID_HOME=~/Library/Android/sdk

# Bootstrap the Gradle wrapper in the fixture project
cd Tests/IntegrationTests/Fixtures/android-sample
gradle wrapper --gradle-version 8.7
cd -
```

Without this setup, Android build tests skip automatically with a descriptive message.

---

## iOS Simulator setup (for `xcodebuild test`)

Tests that run the full test suite on a simulator require a booted device:

```bash
xcrun simctl boot "iPhone 16"
open -a Simulator
```

`xcodebuild build` and `xcodebuild archive` do **not** need a booted simulator.

---

## Signing credentials (for P12 round-trip tests)

The `.requiresP12Credentials` trait gates a CI signing round-trip test that installs a real
certificate into a temporary keychain and verifies the full keychain layer end-to-end.

You need a **development** `.p12` exported from Keychain Access or Xcode — not a distribution
certificate. The test creates and destroys a temporary keychain; it never touches your login
keychain or any production identity.

### Get the base64 value

```bash
base64 -i MyCert.p12 | pbcopy    # copies to clipboard — paste into GitHub secret
```

Verify the round-trip before using it in CI:

```bash
base64 -i MyCert.p12 | base64 -d -o /tmp/verify.p12
security pkcs12 -in /tmp/verify.p12 -noout   # prompts for export password; exits 0 if valid
```

### Set the environment variables

```bash
export SHIPIT_TEST_P12_BASE64="$(base64 -i MyCert.p12)"
export SHIPIT_TEST_P12_PASSWORD=your-p12-export-password
```

Then run:

```bash
swift build && swift test --filter IntegrationTests.SigningTests
```

### Why base64?

GitHub Actions secrets only accept text values. Base64 encodes the binary `.p12` as plain ASCII
so it survives the secret store and environment variable injection. The test decodes it back to a
temp file at runtime.

For local development you have the file on disk, so you can skip the base64 step and just set
`SHIPIT_TEST_P12_BASE64` via the command above.

---

## Binary ID guard

Every credentialed test calls `assertIntegrationScope()` as the first line. This is a
hard assertion that the active bundle ID matches `com.shipitswifty.integration`. It exists
to ensure that even a misconfigured environment cannot accidentally operate against a
production app.

---

## Adding a new integration test

1. Add your test to the appropriate file in `Tests/IntegrationTests/`.
2. If it needs credentials, decorate with the relevant trait:
   - `.requiresASCCredentials`
   - `.requiresGooglePlayCredentials`
   - `.requiresAndroid`
   - `.requiresSimulator`
   - `.requiresSigningIdentity` — local "Apple Development" cert in the default keychain
   - `.requiresP12Credentials` — `SHIPIT_TEST_P12_BASE64` + `SHIPIT_TEST_P12_PASSWORD`
3. Call `assertIntegrationScope(shipfile: ...)` before any credentialed API call.
4. Run `swift test --filter IntegrationTests` locally to verify the test skips cleanly
   without credentials, then verify it passes with credentials sourced from `.env.integration`.

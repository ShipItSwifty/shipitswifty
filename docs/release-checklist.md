# Release Checklist

Use this checklist for each public release. Replace `<version>` with the semantic version being released, for example `0.2.0`.

## Before Tagging

- Confirm the `<version>` tag is correct. (`shipit --version` is stamped from the tag by the
  release workflow; the literal in `Sources/CLI/ShipItCLI.swift` is only a dev fallback.)
- Confirm the repository is clean with `git status --short`.
- Confirm there are no existing conflicting tags with `git tag --list`.
- Confirm `shipitswifty/shipitswifty` is public.
- Confirm `maniramezan/SwiftyShell` is public or otherwise fetchable by SwiftPM consumers.
- Run release build and blocking tests:

```bash
swift build -c release
swift test --enable-code-coverage --skip IntegrationTests
swift test --filter FlutterFixtureIntegrationTests
swift test --filter ReactNativeFixtureIntegrationTests
.build/release/shipit --version
```

Optional real-toolchain e2e smoke checks:

```bash
SHIPIT_E2E=1 swift test --filter FlutterE2ETests
SHIPIT_E2E=1 swift test --filter ReactNativeE2ETests
```

## Tagging

ShipItSwifty uses plain semantic-version tags:

```bash
git tag <version>
git push origin <version>
```

## After Tagging

- The release workflow creates the GitHub Release and (when `HOMEBREW_TAP_TOKEN` is configured)
  auto-updates `ShipItSwifty/homebrew-tap` with the rendered formula. See `docs/homebrew.md`.
- If the tap secret is not configured, complete the manual fallback in `docs/homebrew.md`.
- Verify stable Homebrew install:

```bash
brew tap shipitswifty/tap
brew install shipit
brew test shipitswifty/tap/shipit
shipit --version
```

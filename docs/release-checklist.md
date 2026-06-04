# 0.1.0 Release Checklist

Use this checklist for the first public `0.1.0` release.

## Before Tagging

- Confirm `Sources/CLI/ShipItCLI.swift` reports `0.1.0`.
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
git tag 0.1.0
git push origin 0.1.0
```

## After Tagging

- Create the GitHub Release for `0.1.0`.
- Compute the source tarball SHA256.
- Update and publish `shipitswifty/homebrew-tap` using `docs/homebrew.md`.
- Verify stable Homebrew install:

```bash
brew tap shipitswifty/tap
brew install shipit
brew test shipitswifty/tap/shipit
shipit --version
```

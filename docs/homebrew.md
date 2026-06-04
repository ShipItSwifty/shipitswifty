# Homebrew Release Checklist

> Maintainer-only release checklist. Not mirrored in DocC.

Use this checklist when publishing `shipit` to the Homebrew tap.

## Prerequisites

- `shipitswifty/shipitswifty` is public.
- `maniramezan/SwiftyShell` is public or otherwise fetchable by SwiftPM consumers.
- A tap repository exists, for example `shipitswifty/homebrew-tap`.
- The release tag exists in this repository. For the first release, use `0.1.0`.

## Pre-Tag Validation

Run the release build and blocking test suite before tagging:

```bash
swift build -c release
swift test --enable-code-coverage --skip IntegrationTests
swift test --filter FlutterFixtureIntegrationTests
swift test --filter ReactNativeFixtureIntegrationTests
.build/release/shipit --version
```

Optional real-toolchain e2e smoke checks before tagging:

```bash
SHIPIT_E2E=1 swift test --filter FlutterE2ETests
SHIPIT_E2E=1 swift test --filter ReactNativeE2ETests
```

## Tag the Release

ShipItSwifty uses plain semantic-version tags, not `v`-prefixed tags:

```bash
git tag 0.1.0
git push origin 0.1.0
```

## Compute Release SHA256

Download the source tarball for the new release and compute its SHA256:

```bash
curl -L -o shipit-0.1.0.tar.gz https://github.com/shipitswifty/shipitswifty/archive/refs/tags/0.1.0.tar.gz
shasum -a 256 shipit-0.1.0.tar.gz
```

## Update the Tap Formula

Copy `Formula/shipit.rb` from this repository into the tap repository:

```bash
cp Formula/shipit.rb ../homebrew-tap/Formula/shipit.rb
```

Then add the stable release lines above `head` in the tap copy:

```ruby
url "https://github.com/shipitswifty/shipitswifty/archive/refs/tags/0.1.0.tar.gz"
sha256 "<computed-sha256>"
```

## Validate the Formula Locally

Homebrew 5.1+ requires the formula to live in a tap. For local testing, create or update a tap and copy the formula into it:

```bash
brew tap-new shipitswifty/tap
TAP_DIR="$(brew --repository)/Library/Taps/shipitswifty/homebrew-tap"
mkdir -p "$TAP_DIR/Formula"
cp ../homebrew-tap/Formula/shipit.rb "$TAP_DIR/Formula/shipit.rb"
brew uninstall --force shipit || true
brew install shipitswifty/tap/shipit
brew test shipitswifty/tap/shipit
shipit --version
```

For pre-tag formula testing only, use `--HEAD` or a local `file://` tarball in the tap copy:

```bash
brew install --HEAD shipitswifty/tap/shipit
```

## Publish the Tap Update

Commit and push the formula change in `shipitswifty/homebrew-tap`, then users can install with:

```bash
brew tap shipitswifty/tap
brew install shipit
```

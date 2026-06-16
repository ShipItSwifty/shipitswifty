# Homebrew Release Checklist

> Maintainer-only release checklist. Not mirrored in DocC.

Use this checklist when publishing `shipit` to the Homebrew tap.

## Prerequisites

- `shipitswifty/shipitswifty` is public.
- `maniramezan/SwiftyShell` is public or otherwise fetchable by SwiftPM consumers.
- A tap repository exists, for example `shipitswifty/homebrew-tap`.
- The release tag exists in this repository.

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
git tag <version>
git push origin <version>
```

## Tap Update Is Automated

The tap formula points at the **prebuilt binary tarballs** attached to each GitHub Release
(`shipit-<version>-macos-universal.tar.gz` and `shipit-<version>-linux-static.tar.gz`), not a
source tarball. The release workflow updates the tap automatically:

1. After the macOS + Linux binaries are built and the GitHub Release is created, the
   `Update Homebrew tap` step computes each tarball's SHA256.
2. It renders `Formula/shipit.rb` (this repo's template), substituting the version and both
   SHA256 values. The download URLs use the **bare** tag (no `v` prefix), matching the release.
3. It commits the rendered formula to `ShipItSwifty/homebrew-tap` (`Formula/shipit.rb`).

This requires a repository secret **`HOMEBREW_TAP_TOKEN`** — a fine-grained PAT (or classic token)
with `contents: write` on `ShipItSwifty/homebrew-tap`. If the secret is absent the step logs a
notice and skips; complete the [manual fallback](#manual-fallback) below.

### Manual Fallback

If the automated step was skipped, render and publish the formula by hand from this repo, using
the SHA256 of the **release binary** tarballs (not a source tarball):

```bash
VERSION=<version>
gh release download "$VERSION" -p 'shipit-*-macos-universal.tar.gz' -p 'shipit-*-linux-static.tar.gz'
macos_sha=$(shasum -a 256 "shipit-${VERSION}-macos-universal.tar.gz" | awk '{print $1}')
linux_sha=$(shasum -a 256 "shipit-${VERSION}-linux-static.tar.gz" | awk '{print $1}')
sed -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
    -e "s/MACOS_SHA256_PLACEHOLDER/${macos_sha}/g" \
    -e "s/LINUX_SHA256_PLACEHOLDER/${linux_sha}/g" \
    Formula/shipit.rb > ../homebrew-tap/Formula/shipit.rb
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

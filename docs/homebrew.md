# Homebrew Release Checklist

Use this checklist when publishing `shipit` to a Homebrew tap.

## Prerequisites

- `ArjangConsulting/shipitswifty` is public
- `maniramezan/swiftyshell` is public or otherwise fetchable by SwiftPM consumers
- `ShipItSwifty` has a release tag such as `1.0.0`
- A tap repository exists, for example `ArjangConsulting/homebrew-tap`

## Compute Release SHA256

Download the source tarball for the new release and compute its SHA256:

```bash
curl -L -o shipit-1.0.0.tar.gz https://github.com/ArjangConsulting/shipitswifty/archive/refs/tags/1.0.0.tar.gz
shasum -a 256 shipit-1.0.0.tar.gz
```

## Update the Formula

Copy `Formula/shipit.rb` from this repository into the tap repository:

```bash
cp Formula/shipit.rb ../homebrew-tap/Formula/shipit.rb
```

Then replace:

- `url` with the new tag tarball URL
- `sha256` with the computed checksum

## Validate the Formula Locally

Homebrew 5.1+ requires the formula to live in a tap. For local testing, create a tap and copy the formula into it:

```bash
brew tap-new ArjangConsulting/tap
TAP_DIR="$(brew --repository)/Library/Taps/arjangconsulting/homebrew-tap"
mkdir -p "$TAP_DIR/Formula"
cp Formula/shipit.rb "$TAP_DIR/Formula/shipit.rb"
```

If you are testing before the public repository is reachable from the target machine, edit the tap copy and replace the `head` URL with a local checkout:

```ruby
head "file:///Users/maniramezan/Developer/manman/ShipItSwifty", branch: "main"
```

If you want to test the stable path before a public release exists, create a local tarball and use a local `file://` URL plus its SHA256 in the tap copy.

```bash
brew uninstall --force shipit || true
brew install --HEAD ArjangConsulting/tap/shipit
brew test ArjangConsulting/tap/shipit
shipit --help
```

## Publish the Tap Update

Commit and push the formula change in your tap repository, then users can install with:

```bash
brew tap ArjangConsulting/tap
brew install --HEAD ArjangConsulting/tap/shipit
```

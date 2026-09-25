---
name: verify-linux
description: Build, format-check, and test ShipItSwifty from a Linux session (e.g. a cloud agent container) using Docker and the swift:6.3.1-noble image, and report accurately what could not be verified on Linux. Use before committing when no local Swift toolchain is available.
---

# Verify on Linux

## Run

```bash
make build-linux        # swift build
make test-linux         # swift test, skipping macOS-only targets
```

If the Docker daemon is not running (`Cannot connect to the Docker daemon`), start it in the
background (`dockerd > /tmp/dockerd.log 2>&1 &`) and retry. Behind an HTTPS proxy, pass the proxy
and CA into the container, e.g.:

```bash
docker run --rm --network host \
  -v "$PWD":/workspace -w /workspace \
  -e HTTPS_PROXY -e SSL_CERT_FILE=/path/to/ca.crt -e GIT_SSL_CAINFO=/path/to/ca.crt \
  -v /path/to/ca.crt:/path/to/ca.crt:ro \
  swift:6.3.1-noble swift build --build-tests
```

Mounting a persistent directory at `/workspace/.build` keeps incremental builds fast
(first build ≈ 2–3 min, then seconds).

Targeted runs: `swift test --skip-build --filter 'SuiteOrTestName|Other'`.

## Format

CI runs `swift-format lint --strict --configuration .swift-format` over `Sources` and the test
targets. Format only the files you changed:

```bash
swift format --in-place --configuration .swift-format <changed files>
swift format lint --strict --configuration .swift-format <changed files>
```

## What Linux cannot verify

- `XcodeBuildKit`, `XcodeGenKit`, `IntegrationTests`, and every `#if os(macOS)` block in ShipItKit
  (iOS build/test/archive paths, simctl, xcresult parsing, keychain) are not compiled.
- To catch plain type errors in edited macOS-only code, you may temporarily replace
  `#if os(macOS)` with `#if true` in *that file only*, build the target, ignore errors about
  genuinely Apple-only symbols (`Xcrun`, `Simctl`, `DestinationDiscovery`, OSLog, Security), and
  **restore the file** before committing (`git diff` must not show the flipped guards).
- Always tell the user which changed code paths only macOS CI will compile and run.

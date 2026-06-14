#!/usr/bin/env bash
# Usage: ./scripts/update-formula.sh <version>
# Example: ./scripts/update-formula.sh 0.2.0
#
# Downloads the macOS and Linux release tarballs for the given version,
# computes their SHA256 digests, and patches Formula/shipit.rb in place.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. 0.2.0)" >&2
  exit 1
fi

REPO="ShipItSwifty/shipitswifty"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"
MACOS_TARBALL="shipit-${VERSION}-macos-universal.tar.gz"
LINUX_TARBALL="shipit-${VERSION}-linux-static.tar.gz"
FORMULA="Formula/shipit.rb"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading release assets for v${VERSION}..."
curl -fsSL --output "${TMPDIR}/${MACOS_TARBALL}" "${BASE_URL}/${MACOS_TARBALL}"
curl -fsSL --output "${TMPDIR}/${LINUX_TARBALL}" "${BASE_URL}/${LINUX_TARBALL}"

echo "Computing SHA256..."
if command -v sha256sum &>/dev/null; then
  MACOS_SHA256="$(sha256sum "${TMPDIR}/${MACOS_TARBALL}" | awk '{print $1}')"
  LINUX_SHA256="$(sha256sum "${TMPDIR}/${LINUX_TARBALL}" | awk '{print $1}')"
else
  MACOS_SHA256="$(shasum -a 256 "${TMPDIR}/${MACOS_TARBALL}" | awk '{print $1}')"
  LINUX_SHA256="$(shasum -a 256 "${TMPDIR}/${LINUX_TARBALL}" | awk '{print $1}')"
fi

echo "  macOS: ${MACOS_SHA256}"
echo "  Linux: ${LINUX_SHA256}"

echo "Patching ${FORMULA}..."

# Replace the version line
sed -i.bak "s/^  version \".*\"/  version \"${VERSION}\"/" "${FORMULA}"

# Replace SHA256 placeholders – lines that follow url lines for each platform.
# Strategy: replace the two sha256 lines that contain the placeholder tokens.
sed -i.bak "s/sha256 \"MACOS_SHA256_PLACEHOLDER\"/sha256 \"${MACOS_SHA256}\"/" "${FORMULA}"
sed -i.bak "s/sha256 \"LINUX_SHA256_PLACEHOLDER\"/sha256 \"${LINUX_SHA256}\"/" "${FORMULA}"

rm -f "${FORMULA}.bak"

echo "Done. ${FORMULA} updated for v${VERSION}."
echo ""
echo "Verify with:"
echo "  grep -E 'version|sha256|url' ${FORMULA}"

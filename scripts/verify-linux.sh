#!/usr/bin/env bash
# Verify the Linux build of ShipItSwifty inside the official Swift container.
#
# Mirrors the .github/workflows/ci.yml linux job: swift build, then run the unit
# tests excluding the macOS-only test targets and the integration suite.
#
# Usage:
#   scripts/verify-linux.sh                # build + skipped-test run
#   scripts/verify-linux.sh build          # build only
#   scripts/verify-linux.sh shell          # interactive shell in the container
#   scripts/verify-linux.sh --image swift:6.3-jammy <subcommand>

set -euo pipefail

IMAGE="swift:6.3-jammy"
SUBCOMMAND="ci"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    build|test|ci|shell) SUBCOMMAND="$1"; shift ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="/workspace"

run_in_container() {
  docker run --rm -i \
    -v "${REPO_ROOT}":${WORKDIR} \
    -w ${WORKDIR} \
    -e SWIFT_BUILD_DIR=.build-linux \
    "${IMAGE}" \
    bash -lc "$1"
}

case "${SUBCOMMAND}" in
  build)
    run_in_container "swift --version && swift build --build-path .build-linux"
    ;;
  test)
    run_in_container "swift --version && swift test --build-path .build-linux --skip IntegrationTests --skip XcodeBuildKitTests --skip XcodeGenKitTests"
    ;;
  ci)
    run_in_container "swift --version && swift build --build-path .build-linux && swift test --build-path .build-linux --skip IntegrationTests --skip XcodeBuildKitTests --skip XcodeGenKitTests"
    ;;
  shell)
    docker run --rm -it \
      -v "${REPO_ROOT}":${WORKDIR} \
      -w ${WORKDIR} \
      "${IMAGE}" \
      bash
    ;;
esac

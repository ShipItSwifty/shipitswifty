#!/usr/bin/env bash
# Puts a `shipit` binary on disk and reports its path as the `shipit` output.
#
# Order of preference: an explicit shipit-path; a release matching shipit-version (or the SemVer tag this action was
# pinned at), checked against the release's published checksums; otherwise a build from the action's own checkout,
# which is what a branch or commit pin and this repository's own CI get.
set -euo pipefail

repository="ShipItSwifty/ShipItSwifty"
semver='^[0-9]+\.[0-9]+\.[0-9]+$'

fail() {
  echo "::error title=Cannot install ShipIt::$1"
  exit 1
}

download_release() {
  local version="$1" asset archive base dir
  case "${RUNNER_OS:-}" in
    macOS) asset="macos-universal" ;;
    Linux)
      [[ "$(uname -m)" == "x86_64" ]] || fail "No Linux arm64 build is published; use shipit-path or a macOS runner."
      asset="linux-static"
      ;;
    *) fail "Unsupported runner OS '${RUNNER_OS:-unknown}'." ;;
  esac
  archive="shipit-${version}-${asset}.tar.gz"
  base="https://github.com/${repository}/releases/download/${version}"
  dir="${RUNNER_TEMP}/shipit-${version}"
  mkdir -p "$dir"
  echo "Downloading ShipIt ${version} (${asset})" >&2
  curl -fsSL --retry 3 --retry-delay 2 -o "${dir}/${archive}" "${base}/${archive}" ||
    fail "Could not download ${base}/${archive}. Does release ${version} exist?"
  curl -fsSL --retry 3 --retry-delay 2 -o "${dir}/checksums.txt" "${base}/shipit-${version}-checksums.txt" ||
    fail "Could not download the checksums for release ${version}."
  (cd "$dir" && grep -F " ${archive}" checksums.txt | shasum -a 256 -c - >&2) ||
    fail "Checksum mismatch for ${archive}; refusing to run it."
  tar -xzf "${dir}/${archive}" -C "$dir" shipit
  echo "${dir}/shipit"
}

build_from_source() {
  local root
  root="$(cd "${GITHUB_ACTION_PATH}/../.." && pwd)"
  [[ -f "${root}/Package.swift" ]] || fail "No release to download and no Package.swift at ${root}. Pin the action to a release version, or set shipit-path."
  echo "Building ShipIt from ${root}" >&2
  swift build -c release --product shipit --package-path "$root" >&2
  echo "$(swift build -c release --package-path "$root" --show-bin-path)/shipit"
}

if [[ -n "${INPUT_SHIPIT_PATH:-}" ]]; then
  [[ -x "$INPUT_SHIPIT_PATH" ]] || fail "shipit-path '${INPUT_SHIPIT_PATH}' is not an executable file."
  bin="$INPUT_SHIPIT_PATH"
else
  version="${INPUT_SHIPIT_VERSION:-}"
  if [[ -z "$version" && "${ACTION_REF:-}" =~ $semver ]]; then
    version="$ACTION_REF"
  fi
  if [[ -n "$version" ]]; then
    [[ "$version" =~ $semver ]] || fail "shipit-version must be a bare SemVer such as 0.8.0; got '${version}'."
    bin="$(download_release "$version")"
  else
    bin="$(build_from_source)"
  fi
fi

"$bin" --version
echo "shipit=${bin}" >>"$GITHUB_OUTPUT"

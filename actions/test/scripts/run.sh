#!/usr/bin/env bash
# Runs `shipit test` for the chosen mode and records what happened.
#
# Outputs: exit-code, report-path (when shipit wrote a report), products-archive (build-for-testing).
# In every mode but build-for-testing this script exits 0, so the report and evidence steps still run; the final
# decide step turns the recorded exit code and ShipIt's policy into the job's result.
set -uo pipefail
: "${SHIPIT:?}" "${INPUT_MODE:?}" "${INPUT_SCHEME:?}"

work="${RUNNER_TEMP}/shipit"
mkdir -p "$work"
report="${work}/report.json"
rm -f "$report"

# With no Shipfile, ShipIt reads the project location from the environment.
if [[ -n "${INPUT_WORKSPACE:-}" ]]; then export SHIPIT_APP__WORKSPACE="$INPUT_WORKSPACE"; fi
if [[ -n "${INPUT_PROJECT:-}" ]]; then export SHIPIT_APP__PROJECT="$INPUT_PROJECT"; fi

# One non-empty, trimmed line per element, without relying on bash 4's mapfile (macOS runners can have bash 3.2).
lines() {
  local line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n "$line" ]]; then printf '%s\n' "$line"; fi
  done <<<"$1"
}

args=(test --ci --scheme "$INPUT_SCHEME" --configuration "${INPUT_CONFIGURATION:-Debug}")
if [[ -n "${INPUT_DESTINATION:-}" ]]; then args+=(--destination "$INPUT_DESTINATION"); fi
if [[ -n "${INPUT_TEST_PLAN:-}" ]]; then args+=(--test-plan "$INPUT_TEST_PLAN"); fi

products="${work}/tests.xctestproducts"
case "$INPUT_MODE" in
  build-for-testing)
    rm -rf "$products" "${products}.tar"
    args+=(--build-for-testing-only --test-products-path "$products" --report-path "$report")
    ;;
  test-without-building | full)
    only=()
    while IFS= read -r line; do only+=("$line"); done < <(lines "${INPUT_ONLY_TESTING:-}")
    skip=()
    while IFS= read -r line; do skip+=("$line"); done < <(lines "${INPUT_SKIP_TESTING:-}")
    if ((${#only[@]} > 0)); then args+=(--only-testing "${only[@]}"); fi
    if ((${#skip[@]} > 0)); then args+=(--skip-testing "${skip[@]}"); fi
    if ((INPUT_MAX_ATTEMPTS > 1)); then args+=(--rerun-failed-tests --max-rerun-attempts "$INPUT_MAX_ATTEMPTS"); fi
    if ((INPUT_INFRA_ATTEMPTS > 1)); then args+=(--infrastructure-retry-attempts "$INPUT_INFRA_ATTEMPTS"); fi
    args+=(--report-path "$report")
    if [[ "$INPUT_MODE" == "test-without-building" ]]; then
      archive="$(find "${RUNNER_TEMP}/shipit-products-download" -name '*.tar' -type f 2>/dev/null | head -n 1)"
      if [[ -z "$archive" ]]; then
        echo "::error title=No test products::The test-products artifact held no .tar. Run a build-for-testing job first and pass the same test-products-artifact."
        echo "exit-code=2" >>"$GITHUB_OUTPUT"
        exit 0
      fi
      rm -rf "$products"
      tar -C "$work" -xf "$archive"
      if [[ ! -d "$products" ]]; then
        echo "::error title=Bad test products::${archive} did not contain tests.xctestproducts."
        echo "exit-code=2" >>"$GITHUB_OUTPUT"
        exit 0
      fi
      args+=(--use-test-products "$products")
    fi
    ;;
esac

echo "::group::shipit ${args[*]}"
"$SHIPIT" "${args[@]}"
code=$?
echo "::endgroup::"

echo "exit-code=${code}" >>"$GITHUB_OUTPUT"
if [[ -f "$report" ]]; then echo "report-path=${report}" >>"$GITHUB_OUTPUT"; fi

if [[ "$INPUT_MODE" == "build-for-testing" ]]; then
  if ((code == 0)); then
    # Test products hold executables and symlinks; a plain artifact upload drops permissions, a tar keeps them.
    tar -C "$work" -cf "${products}.tar" "$(basename "$products")"
    echo "products-archive=${products}.tar" >>"$GITHUB_OUTPUT"
  fi
  exit "$code"
fi
exit 0

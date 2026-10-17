#!/usr/bin/env bash
# Turns ShipIt test reports into a job summary, annotations and outputs, and optionally files issues.
#
# Never fails on a test outcome: it records the verdict in `policy-passed` and the decide step enforces it.
set -uo pipefail
: "${SHIPIT:?}" "${INPUT_MODE:?}"

work="${RUNNER_TEMP}/shipit"
mkdir -p "$work"
result="${work}/result.json"
rm -f "$result"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error title=jq missing::The report step reads ShipIt's result with jq, which is preinstalled on GitHub-hosted runners."
  echo "policy-passed=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

reports=()
if [[ "$INPUT_MODE" == "report" ]]; then
  glob="${INPUT_REPORT_GLOB#./}"
  while IFS= read -r path; do reports+=("$path"); done < <(find . -type f -path "./${glob}" | sort)
  if ((${#reports[@]} == 0)); then
    echo "::error title=No reports::No file matched report-glob '${INPUT_REPORT_GLOB}'. Download the shards' shipit-report-* artifacts first."
  fi
elif [[ -n "${RUN_REPORT_PATH:-}" && -f "${RUN_REPORT_PATH}" ]]; then
  reports+=("$RUN_REPORT_PATH")
else
  echo "::error title=No test report::shipit test wrote no report (exit code ${RUN_EXIT_CODE:-unknown}). See the step log above."
fi

if ((${#reports[@]} == 0)); then
  echo "policy-passed=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

args=(ci report --summary-path "${GITHUB_STEP_SUMMARY:-/dev/null}" --annotations --result-path "$result")
if [[ "${INPUT_FAIL_ON_FLAKY:-false}" == "true" ]]; then args+=(--fail-on-flaky); fi
if [[ -n "${ARTIFACT_URL:-}" ]]; then args+=(--artifact-url "$ARTIFACT_URL"); fi
for path in "${reports[@]}"; do args+=(--report "$path"); done
"$SHIPIT" "${args[@]}"
code=$?
# 11 is the policy verdict, already in the result file; anything else means the command itself failed.
if ((code != 0 && code != 11)); then
  echo "::error title=Report failed::shipit ci report exited ${code}."
fi

if [[ -f "$result" ]]; then
  {
    echo "passed=$(jq -r '.passed' "$result")"
    echo "failed=$(jq -r '.failed' "$result")"
    echo "flaky=$(jq -r '.flaky' "$result")"
    echo "has-consistent-failures=$(jq -r '.hasConsistentFailures' "$result")"
    echo "policy-passed=$(jq -r '.policyPassed' "$result")"
    echo "result-path=${result}"
  } >>"$GITHUB_OUTPUT"
else
  echo "policy-passed=false" >>"$GITHUB_OUTPUT"
fi

if [[ "${INPUT_FILE_ISSUES:-false}" == "true" ]]; then
  if [[ -z "${INPUT_ISSUES_REF:-}" ]]; then
    echo "::warning title=Issues skipped::issues-ref is empty (no default branch in the event payload); set it explicitly to file issues."
  else
    iargs=(ci issues --only-ref "$INPUT_ISSUES_REF" --close-after-clean-runs "${INPUT_CLOSE_AFTER:-3}")
    if [[ -n "${ARTIFACT_URL:-}" ]]; then iargs+=(--artifact-url "$ARTIFACT_URL"); fi
    IFS=',' read -r -a labels <<<"${INPUT_ISSUE_LABELS:-}"
    for label in "${labels[@]+"${labels[@]}"}"; do
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
      if [[ -n "$label" ]]; then iargs+=(--label "$label"); fi
    done
    for path in "${reports[@]}"; do iargs+=(--report "$path"); done
    # A failure to file issues (a token without issues: write, say) must not mask or flip the test verdict.
    if ! "$SHIPIT" "${iargs[@]}"; then
      echo "::warning title=Issues not updated::shipit ci issues failed. The job needs 'issues: write'; the test verdict is unaffected."
    fi
  fi
fi
exit 0

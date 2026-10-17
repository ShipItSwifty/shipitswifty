#!/usr/bin/env bash
# The job's result: the test command must have succeeded and the run must pass ShipIt's policy.
# A flaky test that passed on a retry passes unless fail-on-flaky was set (the report step already applied that).
set -uo pipefail

status=0
if [[ -n "${RUN_EXIT_CODE:-}" && "$RUN_EXIT_CODE" != "0" ]]; then
  echo "::error title=ShipIt failed::shipit test exited with ${RUN_EXIT_CODE}."
  status=1
fi
if [[ "${POLICY_PASSED:-}" != "true" ]]; then
  echo "::error title=Tests failed::The run does not pass ShipIt's policy. The job summary lists the failing tests."
  status=1
fi
exit "$status"

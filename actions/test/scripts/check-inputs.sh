#!/usr/bin/env bash
# Fails early, with a message that names the input, instead of deep inside xcodebuild.
set -euo pipefail

case "$INPUT_MODE" in
  build-for-testing | test-without-building | full)
    if [[ -z "$INPUT_SCHEME" ]]; then
      echo "::error title=Missing input::'scheme' is required in mode '$INPUT_MODE'."
      exit 1
    fi
    ;;
  report) ;;
  *)
    echo "::error title=Invalid input::'mode' must be build-for-testing, test-without-building, full or report; got '$INPUT_MODE'."
    exit 1
    ;;
esac

require_integer() {
  local name="$1" value="$2" minimum="$3"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || ((value < minimum)); then
    echo "::error title=Invalid input::'$name' must be an integer >= $minimum; got '$value'."
    exit 1
  fi
}
require_integer max-attempts "$INPUT_MAX_ATTEMPTS" 1
require_integer infrastructure-retry-attempts "$INPUT_INFRA_ATTEMPTS" 1
require_integer close-after-clean-runs "$INPUT_CLOSE_AFTER" 0

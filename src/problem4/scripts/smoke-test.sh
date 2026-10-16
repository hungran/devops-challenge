#!/usr/bin/env bash
# Post-deploy smoke test: wait until the public endpoint reports the expected
# version, then check any extra URLs return 2xx.
#
# Usage: smoke-test.sh <version_url> <expected_version> [extra_url ...]
# Env:   SMOKE_ATTEMPTS (default 20), SMOKE_SLEEP seconds (default 6)
set -euo pipefail

VERSION_URL=${1:?version url required}
EXPECTED=${2:?expected version required}
shift 2
ATTEMPTS=${SMOKE_ATTEMPTS:-20}
SLEEP=${SMOKE_SLEEP:-6}

for ((i = 1; i <= ATTEMPTS; i++)); do
  live=$(curl -fsS --max-time 5 "${VERSION_URL}" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)
  if [[ "${live}" == "${EXPECTED}" ]]; then
    for url in "$@"; do
      if ! curl -fsS --max-time 5 -o /dev/null "${url}"; then
        echo "::error::Smoke test: ${url} did not return 2xx"
        exit 1
      fi
    done
    echo "Smoke test passed: version ${EXPECTED} is live"
    exit 0
  fi
  echo "attempt ${i}/${ATTEMPTS}: live=${live:-<unreachable>} expected=${EXPECTED}"
  sleep "${SLEEP}"
done

echo "::error::Smoke test failed: ${EXPECTED} never became live at ${VERSION_URL}"
exit 1

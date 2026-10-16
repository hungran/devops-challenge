#!/usr/bin/env bash
# Gate: the instance only re-joins the load balancer if the NEW version is
# actually serving. A non-zero exit fails the deployment and, with automatic
# rollback enabled on the deployment group, CodeDeploy redeploys the last
# known-good revision.
set -euo pipefail

PORT=${PORT:-8080}
EXPECTED=$(node -p "require('/opt/backend/current/build-info.json').version")

live_version() {
  curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/version" \
    | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8")).version'
}

for _ in $(seq 1 30); do
  if [ "$(live_version 2>/dev/null || true)" = "${EXPECTED}" ] \
     && curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "Service healthy on version ${EXPECTED}"
    exit 0
  fi
  sleep 2
done

echo "Service failed validation (expected version ${EXPECTED})" >&2
journalctl -u backend.service -n 50 --no-pager >&2 || true
exit 1

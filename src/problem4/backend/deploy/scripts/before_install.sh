#!/usr/bin/env bash
# Prepare a clean landing directory and make sure the runtime user exists.
set -euo pipefail

id -u backend >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin backend

rm -rf /opt/backend/incoming
mkdir -p /opt/backend/incoming /opt/backend/releases

# Fail early (before touching the live release) if the runtime is missing.
command -v node >/dev/null || { echo "node is not installed on this AMI" >&2; exit 1; }

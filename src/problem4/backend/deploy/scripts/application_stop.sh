#!/usr/bin/env bash
# Stop the running service. With an ALB attached to the deployment group,
# CodeDeploy has already deregistered this instance (BlockTraffic) and waited
# for connection draining before this hook runs.
set -euo pipefail

if systemctl list-unit-files backend.service >/dev/null 2>&1; then
  systemctl stop backend.service || true
fi

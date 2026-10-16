#!/usr/bin/env bash
# Move the bundle into an immutable, versioned release directory and point the
# `current` symlink at it atomically. Old releases stay on disk for fast manual
# rollback; only the newest KEEP_RELEASES are retained.
set -euo pipefail

KEEP_RELEASES=5
BASE=/opt/backend
VERSION=$(node -p "require('${BASE}/incoming/build-info.json').version")
RELEASE_DIR="${BASE}/releases/${VERSION}-${DEPLOYMENT_ID:-manual}"

rm -rf "${RELEASE_DIR}"
mv "${BASE}/incoming" "${RELEASE_DIR}"
chown -R root:backend "${RELEASE_DIR}"
chmod -R u=rwX,g=rX,o= "${RELEASE_DIR}"

# Atomic switch: create the new link next to the old one, then rename over it.
ln -sfn "${RELEASE_DIR}" "${BASE}/current.tmp"
mv -Tf "${BASE}/current.tmp" "${BASE}/current"

install -m 0644 "${RELEASE_DIR}/backend.service" /etc/systemd/system/backend.service
systemctl daemon-reload
systemctl enable backend.service

# Prune old releases (never the one we just activated).
find "${BASE}/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
  | sort -rn | tail -n +$((KEEP_RELEASES + 1)) | cut -d' ' -f2- \
  | grep -vxF "${RELEASE_DIR}" | xargs -r rm -rf

echo "Activated release ${RELEASE_DIR}"

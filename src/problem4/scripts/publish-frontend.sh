#!/usr/bin/env bash
# Publish a built SPA to S3 behind CloudFront, safely for users mid-session.
#
# Order matters:
#   1. hashed assets first (immutable, cached for a year, never deleted here)
#   2. other static files
#   3. config.json / version.json (no-cache)
#   4. index.html LAST - the moment it lands, new users get the new build,
#      and every asset it references already exists.
#   5. invalidate only the un-hashed entry points.
# Old hashed assets are removed by an S3 lifecycle rule (e.g. after 30 days),
# not by `sync --delete`, so tabs still running the previous build keep working.
#
# Usage: publish-frontend.sh <dist_dir>
# Env:   SITE_BUCKET, CLOUDFRONT_DISTRIBUTION_ID (+ AWS credentials)
set -euo pipefail

DIST=${1:?dist dir required}
: "${SITE_BUCKET:?}" "${CLOUDFRONT_DISTRIBUTION_ID:?}"

for f in index.html config.json version.json; do
  [[ -f "${DIST}/${f}" ]] || { echo "::error::${DIST}/${f} missing"; exit 1; }
done

aws s3 sync "${DIST}/assets" "s3://${SITE_BUCKET}/assets" \
  --exclude "*.map" \
  --cache-control "public, max-age=31536000, immutable" \
  --only-show-errors

aws s3 sync "${DIST}" "s3://${SITE_BUCKET}" \
  --exclude "assets/*" --exclude "*.map" \
  --exclude "index.html" --exclude "config.json" --exclude "version.json" \
  --cache-control "public, max-age=300" \
  --only-show-errors

for f in config.json version.json; do
  aws s3 cp "${DIST}/${f}" "s3://${SITE_BUCKET}/${f}" \
    --cache-control "no-cache" --content-type "application/json" --only-show-errors
done

aws s3 cp "${DIST}/index.html" "s3://${SITE_BUCKET}/index.html" \
  --cache-control "no-cache" --content-type "text/html; charset=utf-8" --only-show-errors

invalidation_id=$(aws cloudfront create-invalidation \
  --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" \
  --paths "/" "/index.html" "/config.json" "/version.json" \
  --query 'Invalidation.Id' --output text)

echo "Waiting for CloudFront invalidation ${invalidation_id}"
aws cloudfront wait invalidation-completed \
  --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" --id "${invalidation_id}"
echo "Published $(jq -r .version "${DIST}/version.json") to s3://${SITE_BUCKET}"

#!/usr/bin/env bash
# Start a CodeDeploy deployment of a release bundle already stored in S3 and
# block until it succeeds or fails. Used for both normal deploys and rollbacks.
#
# Usage: deploy-backend.sh <s3_key> [description]
# Env:   ARTIFACT_BUCKET, CODEDEPLOY_APP, CODEDEPLOY_GROUP (+ AWS credentials)
set -euo pipefail

KEY=${1:?s3 key required}
DESCRIPTION=${2:-"Deploy ${KEY}"}
: "${ARTIFACT_BUCKET:?}" "${CODEDEPLOY_APP:?}" "${CODEDEPLOY_GROUP:?}"

deployment_id=$(aws deploy create-deployment \
  --application-name "${CODEDEPLOY_APP}" \
  --deployment-group-name "${CODEDEPLOY_GROUP}" \
  --revision "revisionType=S3,s3Location={bucket=${ARTIFACT_BUCKET},key=${KEY},bundleType=tgz}" \
  --file-exists-behavior OVERWRITE \
  --description "${DESCRIPTION:0:100}" \
  --query deploymentId --output text)

echo "CodeDeploy deployment started: ${deployment_id}"
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "deployment_id=${deployment_id}" >> "${GITHUB_OUTPUT}"

# The deployment group itself is configured (outside this repo) with:
#   - CodeDeployDefault.OneAtATime (or a % based config for larger fleets)
#   - ALB traffic control: deregister -> drain -> deploy -> validate -> register
#   - automatic rollback on DEPLOYMENT_FAILURE and DEPLOYMENT_STOP_ON_ALARM
#   - CloudWatch alarms (ALB 5xx rate, target p99 latency) attached
if aws deploy wait deployment-successful --deployment-id "${deployment_id}"; then
  echo "Deployment ${deployment_id} succeeded"
  exit 0
fi

echo "::error::Deployment ${deployment_id} failed"
aws deploy get-deployment --deployment-id "${deployment_id}" \
  --query 'deploymentInfo.{status:status,error:errorInformation,rollback:rollbackInfo}' --output json || true

# Show which lifecycle hook failed on which instance.
# shellcheck disable=SC2016  # backticks are JMESPath literals, not shell
for target in $(aws deploy list-deployment-targets --deployment-id "${deployment_id}" --query 'targetIds' --output text); do
  aws deploy get-deployment-target --deployment-id "${deployment_id}" --target-id "${target}" \
    --query 'deploymentTarget.instanceTarget.{instance:targetId,status:status,failed:lifecycleEvents[?status==`Failed`]}' \
    --output json || true
done
exit 1

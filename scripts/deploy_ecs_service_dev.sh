#!/usr/bin/env bash
set -euo pipefail

service="${1:?usage: deploy_ecs_service_dev.sh <backend|ai> <40-character-commit-sha>}"
image_tag="${2:?usage: deploy_ecs_service_dev.sh <backend|ai> <40-character-commit-sha>}"
cluster="dev-ecs-cluster"
started_seconds=$SECONDS
deployment_result=failed
tmp_definition=""
report_result() {
  local status=$?
  if [ -n "$tmp_definition" ]; then rm -f "$tmp_definition" "$tmp_definition.next"; fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '### Dev ECS deployment\n\n'
      printf '| Service | Result | Duration | SHA |\n|---|---|---:|---|\n'
      printf '| %s | %s | %ss | %s |\n' "$service" "$deployment_result" "$((SECONDS - started_seconds))" "$image_tag"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  return "$status"
}
trap report_result EXIT

case "$service" in
  backend)
    ecs_service="dev-app-task-service"
    container="backend"
    repository="bookjeok-be"
    ;;
  ai)
    ecs_service="dev-ai-service"
    container="ai"
    repository="bookjeok-ai"
    ;;
  *)
    echo "Unsupported Dev ECS service: $service" >&2
    exit 2
    ;;
esac

[[ "$image_tag" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Image tag must be a 40-character commit SHA" >&2
  exit 2
}

digest="$(aws ecr describe-images \
  --repository-name "$repository" \
  --image-ids "imageTag=$image_tag" \
  --query 'imageDetails[0].imageDigest' \
  --output text)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "Could not resolve an immutable ECR digest for $repository:$image_tag" >&2
  exit 1
}
image="${ECR_REGISTRY:?ECR_REGISTRY is required}/$repository@$digest"

service_json="$(aws ecs describe-services \
  --cluster "$cluster" \
  --services "$ecs_service" \
  --output json)"
service_status="$(jq -r '.services[0].status // empty' <<<"$service_json")"
current_task_definition="$(jq -r '.services[0].taskDefinition // empty' <<<"$service_json")"
[[ "$service_status" == ACTIVE && -n "$current_task_definition" ]] || {
  echo "ECS service $ecs_service was not found or is not ACTIVE in $cluster" >&2
  jq -r '.failures[]?.reason' <<<"$service_json" >&2
  exit 1
}

# Reject overlapping or unhealthy deployments before even considering a skip.
jq -e '(.failures | length) == 0 and (.services | length) == 1 and
  (.services[0] | .desiredCount > 0 and
  (.deployments | length) == 1 and .deployments[0].rolloutState == "COMPLETED" and
  .deployments[0].status == "PRIMARY" and
  .deployments[0].taskDefinition == .taskDefinition and
  .runningCount == .desiredCount and .pendingCount == 0)' <<< "$service_json" >/dev/null || {
  echo "Service is not stable; refusing a new deployment" >&2
  exit 1
}
tmp_definition="$(mktemp)"
aws ecs describe-task-definition \
  --task-definition "$current_task_definition" \
  --query taskDefinition \
  --output json \
  | jq --arg container "$container" '
      (.containerDefinitions | map(select(.name == $container)) | length) as $matches
      | if $matches != 1 then error("expected exactly one container named \($container), found \($matches)") else . end
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
    ' > "$tmp_definition"

current_image=$(jq -r --arg container "$container" '.containerDefinitions[] | select(.name == $container) | .image' "$tmp_definition")
if [ "$current_image" = "$image" ]; then
  deployment_result=unchanged
  echo "Stable Dev service already uses requested digest; skipping deployment."
  exit 0
fi
jq --arg container "$container" --arg image "$image" \
  '(.containerDefinitions[] | select(.name == $container) | .image) = $image' \
  "$tmp_definition" > "$tmp_definition.next"
mv "$tmp_definition.next" "$tmp_definition"

new_task_definition="$(aws ecs register-task-definition \
  --cli-input-json "file://$tmp_definition" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)"
echo "Registered $new_task_definition with image $image"

aws ecs update-service \
  --cluster "$cluster" \
  --service "$ecs_service" \
  --task-definition "$new_task_definition" \
  --query 'service.{name:serviceName,status:status,taskDefinition:taskDefinition,desired:desiredCount,running:runningCount}' \
  --output json

# The CLI services-stable waiter checks task counts, not rolloutState. ECS can
# report one healthy deployment while its rollout is still IN_PROGRESS.
echo "Waiting for $ecs_service to complete the requested deployment..."
deadline=$((SECONDS + 1200))
observed_requested=false
while (( SECONDS < deadline )); do
  final_service_json="$(aws ecs describe-services \
    --cluster "$cluster" --services "$ecs_service" --output json)"
  if ! jq -e '.failures | length == 0' <<< "$final_service_json" >/dev/null; then
    echo "Could not describe ECS service $ecs_service" >&2
    jq '.failures' <<< "$final_service_json" >&2
    exit 1
  fi
  if jq -e --arg requested "$new_task_definition" \
    '.services[0].deployments[]? | select(.taskDefinition == $requested)' \
    <<< "$final_service_json" >/dev/null; then
    observed_requested=true
  fi
  if jq -e --arg requested "$new_task_definition" '
    .services[0] | .taskDefinition == $requested and
    (.deployments | length) == 1 and
    .deployments[0].status == "PRIMARY" and
    .deployments[0].taskDefinition == $requested and
    .deployments[0].rolloutState == "COMPLETED" and
    .desiredCount > 0 and .runningCount == .desiredCount and .pendingCount == 0
  ' <<< "$final_service_json" >/dev/null; then
    deployment_result=deployed
    echo "ECS deployment completed on $new_task_definition"
    jq '.services[0] | {serviceName, taskDefinition, desiredCount, runningCount, pendingCount}' <<< "$final_service_json"
    exit 0
  fi
  if jq -e --arg requested "$new_task_definition" \
    '.services[0].deployments[]? | select(.taskDefinition == $requested and .rolloutState == "FAILED")' \
    <<< "$final_service_json" >/dev/null; then
    echo "Requested ECS deployment failed; check circuit-breaker rollback." >&2
    break
  fi
  if [[ "$observed_requested" == true ]] && jq -e --arg requested "$new_task_definition" '
    .services[0] | .taskDefinition != $requested and
    ([.deployments[]? | select(.taskDefinition == $requested)] | length) == 0
  ' <<< "$final_service_json" >/dev/null; then
    echo "Requested ECS deployment was rolled back or superseded." >&2
    break
  fi
  sleep 15
done

echo "ECS deployment did not complete within its 20-minute wait budget or failed." >&2
jq '.services[0] | {taskDefinition, desiredCount, runningCount, pendingCount, deployments, recentEvents: .events[:10]}' <<< "$final_service_json" >&2
exit 1

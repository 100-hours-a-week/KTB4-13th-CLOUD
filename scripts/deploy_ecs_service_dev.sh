#!/usr/bin/env bash
set -euo pipefail

service="${1:?usage: deploy_ecs_service_dev.sh <backend|ai> <40-character-commit-sha>}"
image_tag="${2:?usage: deploy_ecs_service_dev.sh <backend|ai> <40-character-commit-sha>}"
cluster="dev-ecs-cluster"

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

tmp_definition="$(mktemp)"
trap 'rm -f "$tmp_definition"' EXIT
aws ecs describe-task-definition \
  --task-definition "$current_task_definition" \
  --query taskDefinition \
  --output json \
  | jq --arg container "$container" --arg image "$image" '
      (.containerDefinitions | map(select(.name == $container)) | length) as $matches
      | if $matches != 1 then error("expected exactly one container named \($container), found \($matches)") else . end
      | (.containerDefinitions[] | select(.name == $container) | .image) = $image
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
    ' > "$tmp_definition"

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

echo "Waiting for $ecs_service to reach a stable state..."
aws ecs wait services-stable --cluster "$cluster" --services "$ecs_service"
final_service_json="$(aws ecs describe-services \
  --cluster "$cluster" \
  --services "$ecs_service" \
  --output json)"
final_task_definition="$(jq -r '.services[0].taskDefinition // empty' <<<"$final_service_json")"
primary_rollout_state="$(jq -r '.services[0].deployments[]? | select(.status == "PRIMARY") | .rolloutState // empty' <<<"$final_service_json")"

if [[ "$final_task_definition" != "$new_task_definition" || "$primary_rollout_state" != "COMPLETED" ]]; then
  echo "ECS deployment did not complete on the requested task definition." >&2
  echo "Requested: $new_task_definition" >&2
  echo "Current:   ${final_task_definition:-<missing>}" >&2
  echo "PRIMARY rollout state: ${primary_rollout_state:-<missing>}" >&2
  echo "ECS may have automatically rolled back to the previous revision." >&2
  jq -r '.failures[]?.reason' <<<"$final_service_json" >&2
  exit 1
fi

jq '{name: .services[0].serviceName, status: .services[0].status, taskDefinition: .services[0].taskDefinition, desired: .services[0].desiredCount, running: .services[0].runningCount, deployments: [.services[0].deployments[] | {status, rolloutState, taskDefinition, desired: .desiredCount, running: .runningCount}]}' <<<"$final_service_json"

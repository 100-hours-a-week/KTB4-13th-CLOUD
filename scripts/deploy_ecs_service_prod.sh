#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 3 ]; then
  echo "사용법: deploy_ecs_service_prod.sh <backend|ai> <image-uri> <release-sha>" >&2
  exit 2
fi

component=$1
image_uri=$2
release_sha=$3
cluster_name=prod-ecs-cluster

case "$component" in
  backend)
    service_name=prod-app-service
    expected_family=prod-app-task
    container_name=backend
    image_repository=bookjeok-be
    ;;
  ai)
    service_name=prod-ai-service
    expected_family=prod-ai-task
    container_name=ai
    image_repository=bookjeok-ai
    ;;
  *)
    echo "지원하지 않는 컴포넌트입니다: $component" >&2
    exit 2
    ;;
esac

if ! [[ "$release_sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "Release SHA 형식이 올바르지 않습니다." >&2
  exit 2
fi

if ! [[ "$image_uri" =~ ^522688057030\.dkr\.ecr\.${AWS_REGION:?AWS_REGION이 필요합니다}\.amazonaws\.com/${image_repository}@sha256:[0-9a-f]{64}$ ]]; then
  echo "${component}에 허용되지 않은 ECR 이미지입니다: $image_uri" >&2
  exit 2
fi

for command in aws jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "필수 명령을 찾을 수 없습니다: $command" >&2
    exit 1
  }
done

service_json=$(aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "$cluster_name" \
  --services "$service_name" \
  --output json)

if [ "$(jq '.failures | length' <<< "$service_json")" -ne 0 ] \
  || [ "$(jq '.services | length' <<< "$service_json")" -ne 1 ]; then
  echo "ECS 서비스를 정확히 하나 찾지 못했습니다: $service_name" >&2
  jq '{failures, services: [.services[]? | {serviceName, status}]}' <<< "$service_json" >&2
  exit 1
fi

service=$(jq -c '.services[0]' <<< "$service_json")
if [ "$(jq -r '.status' <<< "$service")" != ACTIVE ]; then
  echo "ECS 서비스가 ACTIVE 상태가 아닙니다: $service_name" >&2
  exit 1
fi

if ! jq -e '
  .deploymentConfiguration.deploymentCircuitBreaker.enable == true and
  .deploymentConfiguration.deploymentCircuitBreaker.rollback == true and
  .deploymentConfiguration.minimumHealthyPercent >= 100 and
  .deploymentConfiguration.maximumPercent >= 200
' <<< "$service" >/dev/null; then
  echo "중단 없는 배포를 위한 ECS circuit breaker/용량 설정이 확인되지 않아 변경을 중단합니다." >&2
  exit 1
fi

if ! jq -e --arg family "$expected_family" '
  (.taskDefinition | split("/") | last | split(":") | first) == $family and
  (.deployments | length) == 1 and
  .deployments[0].status == "PRIMARY" and
  .deployments[0].rolloutState == "COMPLETED" and
  .pendingCount == 0 and
  .runningCount == .desiredCount
' <<< "$service" >/dev/null; then
  echo "현재 ECS 배포가 안정 상태가 아니므로 새 배포를 시작하지 않습니다." >&2
  jq '{taskDefinition, desiredCount, runningCount, pendingCount, deployments: [.deployments[] | {status, rolloutState, taskDefinition}]}' <<< "$service" >&2
  exit 1
fi

current_task_definition=$(jq -r '.taskDefinition' <<< "$service")
task_definition_json=$(aws ecs describe-task-definition \
  --region "$AWS_REGION" \
  --task-definition "$current_task_definition" \
  --include TAGS \
  --output json)

container_count=$(jq --arg name "$container_name" \
  '[.taskDefinition.containerDefinitions[] | select(.name == $name)] | length' \
  <<< "$task_definition_json")
if [ "$container_count" -ne 1 ]; then
  echo "Task definition에서 대상 컨테이너를 하나로 특정하지 못했습니다: $container_name" >&2
  exit 1
fi

task_definition_input=$(jq -c \
  --arg family "$expected_family" \
  --arg container "$container_name" \
  --arg image "$image_uri" '
    .taskDefinition
    | select(.family == $family)
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
          .compatibilities, .registeredAt, .registeredBy, .deregisteredAt,
          .taskDefinitionStatus)
    | (.containerDefinitions[] | select(.name == $container).image) = $image
  ' <<< "$task_definition_json")

tags=$(jq -c '.tags // []' <<< "$task_definition_json")
register_args=(
  --region "$AWS_REGION"
  --cli-input-json "$task_definition_input"
  --output json
)
# ECS rejects an explicitly empty --tags list. Omit the option when the source
# task definition has no tags; preserve existing tags when there are any.
if [ "$(jq 'length' <<< "$tags")" -gt 0 ]; then
  register_args+=(--tags "$tags")
fi
new_task_definition=$(aws ecs register-task-definition "${register_args[@]}")
new_task_definition_arn=$(jq -er '.taskDefinition.taskDefinitionArn' <<< "$new_task_definition")

echo "${component} 이미지와 SHA가 해당 ECS 서비스에만 연결됩니다: $service_name ($release_sha)"
echo "새 task definition을 등록했습니다: $new_task_definition_arn"
aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$cluster_name" \
  --service "$service_name" \
  --task-definition "$new_task_definition_arn" \
  --output json >/dev/null

echo "ECS rolling 배포 및 circuit-breaker 자동 롤백을 확인합니다."
observed_new_deployment=false
for attempt in $(seq 1 120); do
  current_service_json=$(aws ecs describe-services \
    --region "$AWS_REGION" \
    --cluster "$cluster_name" \
    --services "$service_name" \
    --output json)
  current_service=$(jq -c '.services[0]' <<< "$current_service_json")

  primary_task_definition=$(jq -r '.deployments[] | select(.status == "PRIMARY") | .taskDefinition' <<< "$current_service")
  primary_rollout_state=$(jq -r '.deployments[] | select(.status == "PRIMARY") | (.rolloutState // "UNKNOWN")' <<< "$current_service")
  running_count=$(jq -r '.runningCount' <<< "$current_service")
  pending_count=$(jq -r '.pendingCount' <<< "$current_service")
  desired_count=$(jq -r '.desiredCount' <<< "$current_service")

  if jq -e --arg task_definition "$new_task_definition_arn" \
    '.deployments[] | select(.taskDefinition == $task_definition)' \
    <<< "$current_service" >/dev/null; then
    observed_new_deployment=true
  fi

  if [ "$primary_task_definition" = "$new_task_definition_arn" ] \
    && [ "$primary_rollout_state" = COMPLETED ] \
    && [ "$running_count" -eq "$desired_count" ] \
    && [ "$pending_count" -eq 0 ] \
    && [ "$(jq '.deployments | length' <<< "$current_service")" -eq 1 ]; then
    echo "${component} ECS 배포가 안정 상태에 도달했습니다: $service_name"
    exit 0
  fi

  if jq -e --arg task_definition "$new_task_definition_arn" \
    '.deployments[] | select(.taskDefinition == $task_definition and .rolloutState == "FAILED")' \
    <<< "$current_service" >/dev/null; then
    echo "새 ECS 배포가 실패했습니다. circuit breaker의 자동 롤백 결과를 확인하세요." >&2
    jq '{taskDefinition, desiredCount, runningCount, pendingCount, deployments: [.deployments[] | {status, rolloutState, taskDefinition}], recentEvents: [.events[:10][]?.message]}' <<< "$current_service" >&2
    exit 1
  fi

  if [ "$observed_new_deployment" = true ] \
    && [ "$primary_task_definition" != "$new_task_definition_arn" ] \
    && [ "$running_count" -eq "$desired_count" ] \
    && [ "$pending_count" -eq 0 ] \
    && ! jq -e --arg task_definition "$new_task_definition_arn" \
      '.deployments[] | select(.taskDefinition == $task_definition)' \
      <<< "$current_service" >/dev/null; then
    echo "ECS가 새 task definition을 안정 상태로 만들지 못했고 기존 배포로 돌아왔습니다." >&2
    jq '{taskDefinition, desiredCount, runningCount, pendingCount, deployments: [.deployments[] | {status, rolloutState, taskDefinition}], recentEvents: [.events[:10][]?.message]}' <<< "$current_service" >&2
    exit 1
  fi

  sleep 15
done

echo "ECS 배포가 30분 안에 안정 상태에 도달하지 않았습니다." >&2
jq '{taskDefinition, desiredCount, runningCount, pendingCount, deployments: [.deployments[] | {status, rolloutState, taskDefinition}], recentEvents: [.events[:10][]?.message]}' <<< "$current_service" >&2
exit 1

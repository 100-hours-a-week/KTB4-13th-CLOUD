#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 8 ]; then
  echo "사용법: deploy_ai.sh <deploy-dir> <compose-file> <service> <image-uri> <release-sha> <aws-region> <ecr-registry> <health-url>" >&2
  exit 2
fi

deploy_dir=$1
compose_file=$2
service_name=$3
image_uri=$4
release_sha=$5
aws_region=$6
ecr_registry=$7
health_url=$8

env_file="$deploy_dir/.env"
compose_override_file=""
ssm_env_file=""
current_file="$deploy_dir/current-ai-release.env"
previous_file="$deploy_dir/previous-ai-release.env"
candidate_file="$deploy_dir/candidate-ai-release.env"

for command in aws docker curl grep sed tail cp mv sleep flock stat mktemp; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "필수 명령을 찾을 수 없습니다: $command" >&2
    exit 1
  }
done

cd "$deploy_dir"

echo "ECR에 Docker 로그인합니다."
aws ecr get-login-password --region "$aws_region" \
  | docker login --username AWS --password-stdin "$ecr_registry" >/dev/null

owner=$(stat -c '%u' .)
mode=$(stat -c '%a' .)
if [ "$owner" -ne 0 ] || (( (8#$mode & 8#022) != 0 )); then
  echo "배포 디렉터리는 root 소유이고 group/other 쓰기 권한이 없어야 합니다." >&2
  exit 1
fi

[ -f "$compose_file" ] || { echo "Compose 파일을 찾을 수 없습니다: $compose_file" >&2; exit 1; }
[ -f "$env_file" ] || { echo "환경변수 파일을 찾을 수 없습니다: $env_file" >&2; exit 1; }

exec 9>"$deploy_dir/.ai-deploy.lock"
flock -n 9 || { echo "다른 AI 배포가 진행 중입니다." >&2; exit 1; }

read_release() {
  local file=$1
  [ -f "$file" ] || return 1
  release_image=$(sed -n 's/^AI_IMAGE=//p' "$file" | tail -n 1)
  release_sha=$(sed -n 's/^RELEASE_SHA=//p' "$file" | tail -n 1)
  [ -n "$release_image" ] && [ -n "$release_sha" ]
}

if [ -f "$current_file" ]; then
  cp "$current_file" "$previous_file"
fi

printf 'AI_IMAGE=%s\nRELEASE_SHA=%s\n' "$image_uri" "$release_sha" > "$candidate_file"

run_compose() {
  local target_image=$1
  local target_sha=$2
  shift 2
  AI_IMAGE="$target_image" RELEASE_SHA="$target_sha" \
  AWS_REGION="$aws_region" \
  AI_SERVICE_TOKEN="$ai_service_token" \
    docker compose --env-file "$env_file" -f "$compose_file" -f "$compose_override_file" "$@"
}

load_ai_secrets() {
  echo "Parameter Store에서 AI 운영 설정을 읽습니다."
  ssm_env_file=$(mktemp "$deploy_dir/.ai-ssm-env.XXXXXX")
  aws ssm get-parameters-by-path \
    --path /bookjeok/prod/ai \
    --recursive --with-decryption \
    --query 'Parameters[*].[Name,Value]' --output text \
    | while IFS=$'\t' read -r parameter_name parameter_value; do
        [ -n "$parameter_name" ] || continue
        variable_name=${parameter_name##*/}
        printf '%s=%s\n' "$variable_name" "$parameter_value"
      done > "$ssm_env_file"

  ai_service_token=$(sed -n 's/^AI_SERVICE_TOKEN=//p' "$ssm_env_file" | tail -n 1)

  [ -n "$ai_service_token" ] || {
    echo "SSM /bookjeok/prod/ai/AI_SERVICE_TOKEN 값이 없거나 비어 있습니다." >&2
    exit 1
  }
}

configure_cloudwatch_logging() {
  compose_override_file=$(mktemp "$deploy_dir/.ai-compose-override.XXXXXX.yml")
  printf 'services:\n  %s:\n    env_file:\n      - %s\n    logging:\n      driver: awslogs\n      options:\n        awslogs-region: ${AWS_REGION}\n        awslogs-group: /bookjeok/ai\n        awslogs-stream: ai/${HOSTNAME}\n        awslogs-create-group: "true"\n' "$service_name" "$ssm_env_file" > "$compose_override_file"
}

cleanup_unused_docker_storage() {
  local repository=$1
  local keep_current=${2:-}
  local keep_previous=${3:-}
  local current_id previous_id image_id

  echo "사용하지 않는 Docker 이미지와 중지된 컨테이너를 정리합니다."
  docker container prune --force >/dev/null || true
  docker image prune --force >/dev/null || true

  current_id=$(docker image inspect -q "$keep_current" 2>/dev/null || true)
  previous_id=$(docker image inspect -q "$keep_previous" 2>/dev/null || true)
  while read -r image_id; do
    [ -n "$image_id" ] || continue
    [ "$image_id" = "$current_id" ] && continue
    [ "$image_id" = "$previous_id" ] && continue
    docker image rm "$image_id" >/dev/null 2>&1 || true
  done < <(docker image ls -q "$repository" | sort -u)
}

rollback() {
  if read_release "$previous_file"; then
    echo "이전 AI 이미지로 Rollback합니다." >&2
    run_compose "$release_image" "$release_sha" pull "$service_name"
    run_compose "$release_image" "$release_sha" up -d --no-deps "$service_name"
  fi
}

diagnose_failed_deploy() {
  local container_id

  echo "새 AI 이미지 헬스체크에 실패했습니다. 롤백 전 상태를 출력합니다." >&2
  echo "--- 마지막 헬스체크 응답 ---" >&2
  printf '%s\n' "${last_health_response:-응답 없음}" >&2
  echo "--- 컨테이너 상태 ---" >&2
  run_compose "$image_uri" "$release_sha" ps "$service_name" >&2 || true
  container_id=$(run_compose "$image_uri" "$release_sha" ps -q "$service_name" 2>/dev/null || true)
  if [ -n "$container_id" ]; then
    echo "--- 컨테이너 종료 상태 ---" >&2
    docker inspect --format 'status={{.State.Status}} exit_code={{.State.ExitCode}} error={{.State.Error}} started_at={{.State.StartedAt}}' "$container_id" >&2 || true
    echo "--- AI 컨테이너 로그 (최근 200줄) ---" >&2
    docker logs --tail 200 "$container_id" 2>&1 >&2 || true
  fi
}

trap 'rm -f -- "$candidate_file" "$compose_override_file" "$ssm_env_file"' EXIT

load_ai_secrets
configure_cloudwatch_logging

previous_image=""
if read_release "$previous_file"; then
  previous_image="$release_image"
fi
cleanup_unused_docker_storage "${image_uri%@*}" "" "$previous_image"
run_compose "$image_uri" "$release_sha" pull "$service_name"
run_compose "$image_uri" "$release_sha" up -d --no-deps "$service_name"

ready=0
last_health_response="응답 없음"
body=""
for _ in $(seq 1 30); do
  if body=$(curl --fail --silent --show-error --max-time 5 --write-out '\n__HTTP_STATUS__:%{http_code}' "$health_url"); then
    last_health_response="$body"
    ready=1
    break
  fi
  last_health_response="$body"
  sleep 5
done

if [ "$ready" -ne 1 ]; then
  diagnose_failed_deploy
  rollback || true
  exit 1
fi

mv "$candidate_file" "$current_file"
cleanup_unused_docker_storage "${image_uri%@*}" "$image_uri" "$previous_image"
echo "AI 배포가 완료되었습니다: $release_sha"

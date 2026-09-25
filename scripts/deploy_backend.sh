#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 8 ]; then
  echo "사용법: deploy_backend.sh <deploy-dir> <compose-file> <service> <image-uri> <release-sha> <aws-region> <ecr-registry> <health-url>" >&2
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
current_file="$deploy_dir/current-backend-release.env"
previous_file="$deploy_dir/previous-backend-release.env"
candidate_file="$deploy_dir/candidate-backend-release.env"

for command in aws docker curl grep sed tail cp mv sleep flock stat; do
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

exec 9>"$deploy_dir/.backend-deploy.lock"
flock -n 9 || { echo "다른 Backend 배포가 진행 중입니다." >&2; exit 1; }

read_release() {
  local file=$1
  [ -f "$file" ] || return 1
  release_image=$(sed -n 's/^BACKEND_IMAGE=//p' "$file" | tail -n 1)
  release_sha=$(sed -n 's/^RELEASE_SHA=//p' "$file" | tail -n 1)
  [ -n "$release_image" ] && [ -n "$release_sha" ]
}

if [ -f "$current_file" ]; then
  cp "$current_file" "$previous_file"
fi

printf 'BACKEND_IMAGE=%s\nRELEASE_SHA=%s\n' "$image_uri" "$release_sha" > "$candidate_file"

run_compose() {
  local target_image=$1
  local target_sha=$2
  shift 2
  BACKEND_IMAGE="$target_image" RELEASE_SHA="$target_sha" \
    docker compose --env-file "$env_file" -f "$compose_file" "$@"
}

rollback() {
  if read_release "$previous_file"; then
    echo "이전 Backend 이미지로 Rollback합니다." >&2
    run_compose "$release_image" "$release_sha" pull "$service_name"
    run_compose "$release_image" "$release_sha" up -d --no-deps "$service_name"
  fi
}

trap 'rm -f -- "$candidate_file"' EXIT

run_compose "$image_uri" "$release_sha" pull "$service_name"
run_compose "$image_uri" "$release_sha" up -d --no-deps "$service_name"

ready=0
for _ in $(seq 1 30); do
  if body=$(curl --fail --silent --show-error --max-time 5 "$health_url") \
    && grep -Eq '"success"[[:space:]]*:[[:space:]]*true' <<< "$body"; then
    ready=1
    break
  fi
  sleep 5
done

if [ "$ready" -ne 1 ]; then
  rollback || true
  exit 1
fi

mv "$candidate_file" "$current_file"
echo "Backend 배포가 완료되었습니다: $release_sha"

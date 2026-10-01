#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 7 ]; then
  echo "사용법: deploy_service_dev.sh <deploy-dir> <compose-file> <service> <image-uri> <aws-region> <ecr-registry> <health-url>" >&2
  exit 2
fi

deploy_dir=$1
compose_file=$2
service_name=$3
image_uri=$4
aws_region=$5
ecr_registry=$6
health_url=$7

for command in aws docker curl; do
  command -v "$command" >/dev/null 2>&1 || { echo "필수 명령을 찾을 수 없습니다: $command" >&2; exit 1; }
done
[ -d "$deploy_dir" ] || { echo "배포 디렉터리를 찾을 수 없습니다: $deploy_dir" >&2; exit 1; }
[ -f "$deploy_dir/$compose_file" ] || { echo "Compose 파일을 찾을 수 없습니다: $deploy_dir/$compose_file" >&2; exit 1; }
[ -f "$deploy_dir/.env" ] || { echo "Dev .env 파일을 찾을 수 없습니다: $deploy_dir/.env" >&2; exit 1; }

cd "$deploy_dir"
aws ecr get-login-password --region "$aws_region" | docker login --username AWS --password-stdin "$ecr_registry" >/dev/null
AI_IMAGE="$image_uri" BACKEND_IMAGE="$image_uri" docker compose --env-file .env -f "$compose_file" pull "$service_name"
AI_IMAGE="$image_uri" BACKEND_IMAGE="$image_uri" docker compose --env-file .env -f "$compose_file" up -d --no-deps "$service_name"

for _ in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 5 "$health_url" >/dev/null; then
    echo "Dev 배포가 완료되었습니다: $service_name"
    exit 0
  fi
  sleep 5
done

echo "Dev Health Check에 실패했습니다: $health_url" >&2
docker compose --env-file .env -f "$compose_file" ps "$service_name" >&2 || true
docker compose --env-file .env -f "$compose_file" logs --tail 200 "$service_name" >&2 || true
exit 1

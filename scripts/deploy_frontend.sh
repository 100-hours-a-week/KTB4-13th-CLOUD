#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
  echo "사용법: deploy_frontend.sh <dist-dir> <frontend-sha> <s3-bucket> <cloudfront-distribution-id>" >&2
  exit 2
fi

dist_dir=$1
frontend_sha=$2
s3_bucket=$3
distribution_id=$4

if [ ! -d "$dist_dir" ] || [ ! -f "$dist_dir/index.html" ]; then
  echo "Frontend build 결과를 찾을 수 없습니다: $dist_dir" >&2
  exit 1
fi

if ! [[ "$frontend_sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "Frontend SHA가 올바르지 않습니다." >&2
  exit 1
fi

if [ -z "$distribution_id" ]; then
  echo "CloudFront Distribution ID가 비어 있습니다." >&2
  exit 1
fi

command -v aws >/dev/null 2>&1 || { echo "aws 명령을 찾을 수 없습니다." >&2; exit 1; }

release_prefix="s3://${s3_bucket}/releases/${frontend_sha}"

echo "Frontend Release 업로드를 시작합니다: $release_prefix"
if ! aws s3 sync "$dist_dir/" "$release_prefix" \
  --delete \
  --cache-control 'public,max-age=31536000,immutable'; then
  echo "Frontend 배포 실패: S3 Release 업로드 단계" >&2
  exit 1
fi

echo "Frontend 진입점 전환을 시작합니다: s3://${s3_bucket}/index.html"
if ! aws s3 cp "$release_prefix/index.html" "s3://${s3_bucket}/index.html" \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html; charset=utf-8'; then
  echo "Frontend 배포 실패: index.html 전환 단계" >&2
  exit 1
fi

echo "CloudFront 캐시 무효화를 시작합니다: $distribution_id"
if ! invalidation_id=$(aws cloudfront create-invalidation \
  --distribution-id "$distribution_id" \
  --paths '/*' \
  --query 'Invalidation.Id' \
  --output text); then
  echo "Frontend 배포 실패: CloudFront 캐시 무효화 단계" >&2
  exit 1
fi

echo "CloudFront 캐시 무효화가 생성되었습니다: $invalidation_id"
echo "Frontend Release가 전환되었습니다: $frontend_sha"

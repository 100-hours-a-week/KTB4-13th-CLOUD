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

aws s3 sync "$dist_dir/" "$release_prefix" \
  --delete \
  --cache-control 'public,max-age=31536000,immutable'

aws s3 cp "$release_prefix/index.html" "s3://${s3_bucket}/index.html" \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html; charset=utf-8'

aws cloudfront create-invalidation \
  --distribution-id "$distribution_id" \
  --paths '/*' >/dev/null

echo "Frontend Release가 전환되었습니다: $frontend_sha"

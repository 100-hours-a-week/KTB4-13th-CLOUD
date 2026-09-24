#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 2 ]; then
  echo "사용법: verify-release.sh <manifest> <release-tag>" >&2
  exit 2
fi

manifest=$1
release_tag=$2

if [ ! -f "$manifest" ]; then
  echo "Release Manifest를 찾을 수 없습니다: $manifest" >&2
  exit 1
fi

if ! [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tag는 vMAJOR.MINOR.PATCH 형식이어야 합니다: $release_tag" >&2
  exit 1
fi

read_value() {
  local key=$1
  sed -nE "s/^${key}:[[:space:]]*([^[:space:]#]+).*$/\\1/p" "$manifest" | head -n 1
}

manifest_release=$(read_value release)
frontend_sha=$(read_value frontend_sha)
backend_sha=$(read_value backend_sha)
ai_sha=$(read_value ai_sha)

if [ "$manifest_release" != "$release_tag" ]; then
  echo "Manifest release와 Git tag가 다릅니다: $manifest_release != $release_tag" >&2
  exit 1
fi

for pair in "frontend_sha:$frontend_sha" "backend_sha:$backend_sha" "ai_sha:$ai_sha"; do
  key=${pair%%:*}
  value=${pair#*:}
  if ! [[ "$value" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "${key}는 7~40자의 lowercase Git SHA여야 합니다." >&2
    exit 1
  fi
done

printf 'release=%s\nfrontend_sha=%s\nbackend_sha=%s\nai_sha=%s\n' \
  "$manifest_release" "$frontend_sha" "$backend_sha" "$ai_sha"

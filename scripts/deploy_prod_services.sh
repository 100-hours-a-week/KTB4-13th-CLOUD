#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
  echo 'Usage: deploy_prod_services.sh <ai-image> <ai-sha> <backend-image> <backend-sha>' >&2
  exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
started_seconds=$SECONDS
summary_dir=$(mktemp -d)
finish() {
  local status=$?
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '### ECS deployment\n\n'
      printf '| Service | Result | Duration | SHA |\n|---|---|---:|---|\n'
      cat "$summary_dir/ai" "$summary_dir/backend" 2>/dev/null || true
      printf '\nECS phase elapsed: %ss; exit status: %s\n' "$((SECONDS - started_seconds))" "$status"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  rm -rf "$summary_dir"
  return "$status"
}
trap finish EXIT

# Wait for both rollouts even if one fails. FE activation requires both to succeed.
GITHUB_STEP_SUMMARY="$summary_dir/ai" bash "$script_dir/deploy_ecs_service_prod.sh" ai "$1" "$2" &
ai_pid=$!
GITHUB_STEP_SUMMARY="$summary_dir/backend" bash "$script_dir/deploy_ecs_service_prod.sh" backend "$3" "$4" &
backend_pid=$!
status=0
wait "$ai_pid" || status=1
wait "$backend_pid" || status=1
exit "$status"

#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 3 ]; then
  echo "사용법: send-ssm.sh <instance-id> <script> <argument>..." >&2
  exit 2
fi

instance_id=$1
script=$2
shift 2
encoded_script=$(base64 --wrap=0 "$script")
remote_args=''
for arg in "$@"; do
  remote_args+=" $(printf '%q' "$arg")"
done

remote_command=$(cat <<EOF
set -eu
remote_script=\$(mktemp /tmp/cloud-deploy.XXXXXX)
trap 'rm -f "\$remote_script"' EXIT
printf '%s' '$encoded_script' | base64 -d > "\$remote_script"
chmod 700 "\$remote_script"
"\$remote_script"$remote_args
EOF
)
parameters=$(jq -cn --arg command "$remote_command" '{commands: [$command]}')
command_id=$(aws ssm send-command --instance-ids "$instance_id" --document-name AWS-RunShellScript --comment "Cloud CD deployment" --timeout-seconds 900 --parameters "$parameters" --query 'Command.CommandId' --output text)

deadline=$((SECONDS + 900))
while true; do
  invocation=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" 2>/dev/null || true)
  status=$(jq -r '.Status // empty' <<< "$invocation")
  case "$status" in
    Success) jq -r '.StandardOutputContent' <<< "$invocation"; jq -r '.StandardErrorContent' <<< "$invocation" >&2; exit 0 ;;
    Failed|Cancelled|TimedOut|Cancelling) jq -r '.StandardOutputContent' <<< "$invocation"; jq -r '.StandardErrorContent' <<< "$invocation" >&2; exit 1 ;;
  esac
  if (( SECONDS >= deadline )); then echo "SSM 명령 제한 시간을 초과했습니다." >&2; exit 1; fi
  sleep 5
done

#!/bin/bash
set -Eeuo pipefail

: "${FLY_API_TOKEN:?FLY_API_TOKEN is required}"
: "${TARGET_APP:?TARGET_APP is required}"
: "${TARGET_MACHINE:?TARGET_MACHINE is required}"

machine_state() {
  flyctl machine list --app "$TARGET_APP" --json \
    | jq --raw-output \
      --arg machine "$TARGET_MACHINE" \
      '.[] | select(.id == $machine) | .state'
}

started=0
for _ in {1..60}; do
  state="$(machine_state)"
  case "$state" in
    started)
      started=1
      break
      ;;
    stopped|suspended)
      flyctl machine start "$TARGET_MACHINE" --app "$TARGET_APP"
      ;;
    starting|stopping|replacing)
      ;;
    *)
      echo "Unexpected target Machine state: ${state:-missing}" >&2
      exit 1
      ;;
  esac
  sleep 5
done

if [[ "$started" -ne 1 ]]; then
  echo "Target Machine did not start within five minutes" >&2
  exit 1
fi

ssh_ready=0
for _ in {1..60}; do
  if flyctl ssh console \
    --app "$TARGET_APP" \
    --command true \
    >/dev/null 2>&1; then
    ssh_ready=1
    break
  fi
  sleep 5
done

if [[ "$ssh_ready" -ne 1 ]]; then
  echo "Target Machine SSH did not become ready within five minutes" >&2
  exit 1
fi

flyctl ssh console \
  --app "$TARGET_APP" \
  --command /usr/local/bin/backup-server-data

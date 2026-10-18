#!/bin/bash
set -Eeuo pipefail

required_variables=(
  RESTIC_REPOSITORY
  RESTIC_PASSWORD
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  RCON_PASSWORD
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable $variable is not set" >&2
    exit 1
  fi
done

lock_directory="/tmp/minecraft-restic-backup.lock"
if ! mkdir "$lock_directory" 2>/dev/null; then
  echo "Another Minecraft backup is already running" >&2
  exit 1
fi

saves_disabled=0
cleanup() {
  if [[ "$saves_disabled" -eq 1 ]]; then
    rcon-cli save-on || true
  fi
  rmdir "$lock_directory"
}
trap cleanup EXIT

server_ready=0
for _ in {1..60}; do
  if rcon-cli list >/dev/null 2>&1; then
    server_ready=1
    break
  fi
  sleep 5
done

if [[ "$server_ready" -ne 1 ]]; then
  echo "Minecraft did not become ready within five minutes" >&2
  exit 1
fi

backup_paths=()
candidate_paths=(
  /data/world
  /data/world_nether
  /data/world_the_end
  /data/plugins
  /data/config
  /data/server.properties
  /data/bukkit.yml
  /data/spigot.yml
  /data/commands.yml
  /data/permissions.yml
  /data/ops.json
  /data/whitelist.json
  /data/banned-ips.json
  /data/banned-players.json
  /data/usercache.json
  /data/version_history.json
)

for path in "${candidate_paths[@]}"; do
  if [[ -e "$path" ]]; then
    backup_paths+=("$path")
  fi
done

if [[ ! -d /data/world || ! -d /data/world_nether || ! -d /data/world_the_end ]]; then
  echo "One or more required world directories are missing" >&2
  exit 1
fi

echo "Starting Minecraft backup"
rcon-cli save-off
saves_disabled=1
rcon-cli save-all flush

restic backup \
  --host minecraft-on-demand-007a5d \
  --tag minecraft-fly \
  "${backup_paths[@]}"

rcon-cli save-on
saves_disabled=0

restic forget \
  --host minecraft-on-demand-007a5d \
  --keep-daily 7 \
  --prune

echo "Minecraft backup completed"

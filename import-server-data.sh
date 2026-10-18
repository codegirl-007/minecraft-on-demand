#!/bin/bash
set -Eeuo pipefail

archive="/data/import/server-data.tar.gz"
expected_sha256="0c2a37818b506c4df6d5b7ab9e6fe25b2c3147dd43776613dcb9438734d45f55"

if [[ ! -f "$archive" ]]; then
  exit 0
fi

actual_sha256="$(sha256sum "$archive" | cut -d' ' -f1)"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Import archive checksum mismatch; refusing to replace server data" >&2
  exit 1
fi

staging="/data/.migration-staging"
if [[ -e "$staging" ]]; then
  echo "Migration staging path already exists; refusing to overwrite it" >&2
  exit 1
fi

mkdir "$staging"
tar --extract --gzip --no-same-owner --file "$archive" --directory "$staging"

required_files=(
  "world/level.dat"
  "server.properties"
  "plugins/Geyser-Spigot.jar"
  "plugins/Geyser-Spigot/config.yml"
  "plugins/floodgate-spigot.jar"
  "plugins/floodgate/key.pem"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$staging/$required_file" ]]; then
    echo "Import archive is missing $required_file; refusing to replace server data" >&2
    exit 1
  fi
done

sed -i \
  '0,/^  address: 0\.0\.0\.0$/s//  address: fly-global-services/' \
  "$staging/plugins/Geyser-Spigot/config.yml"

if ! grep -q '^  address: fly-global-services$' \
  "$staging/plugins/Geyser-Spigot/config.yml"; then
  echo "Failed to configure Geyser for Fly UDP; refusing to replace server data" >&2
  exit 1
fi

backup="/data/pre-import-backup-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$backup"

items=(
  world
  world_nether
  world_the_end
  plugins
  config
  ops.json
  whitelist.json
  banned-ips.json
  banned-players.json
  usercache.json
  server.properties
  bukkit.yml
  commands.yml
  help.yml
  permissions.yml
  spigot.yml
)

for item in "${items[@]}"; do
  if [[ -e "/data/$item" ]]; then
    mv "/data/$item" "$backup/"
  fi

  if [[ -e "$staging/$item" ]]; then
    mv "$staging/$item" "/data/"
  fi
done

mv "$archive" "$backup/server-data.tar.gz"
rmdir "$staging" /data/import
touch "$backup/import-completed"

echo "Imported server data; previous Fly data is in $backup"

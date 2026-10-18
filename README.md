# On-demand Paper server on Fly.io

This project runs a small Paper server with Java and Bedrock cross-play that:

- starts for Java TCP 25565 or Bedrock UDP 19132 traffic;
- stores the world on a persistent Fly Volume;
- saves and stops 15 minutes after the last player leaves;
- stays stopped after a clean idle shutdown.

## Expected resources and cost

The Machine has 1 performance CPU and 8 GB RAM, with 6 GB assigned to
Minecraft. CPU and RAM are billed only while the Machine runs. The 10 GB
volume, stopped Machine root filesystem, snapshots, and dedicated IPv4 address
continue to incur charges while it is stopped.

Bedrock traffic requires a dedicated IPv4 address because Fly does not support
public UDP over shared IPv4 or IPv6. Fly currently charges $2/month for a
dedicated IPv4 address.

## 1. Install and authenticate flyctl

Follow Fly's install instructions:

https://fly.io/docs/flyctl/install/

Then sign in:

```sh
fly auth login
```

## 2. Choose a region

The configuration defaults to San Jose (`sjc`). Pick a region close to the
players and change `primary_region` in `fly.toml` if needed:

```sh
fly platform regions
```

## 3. Create and deploy the app

Fly app names are globally unique. Replace `YOUR_APP_NAME` in every command:

```sh
fly apps create YOUR_APP_NAME
fly ips allocate-v4 -a YOUR_APP_NAME
fly deploy --ha=false -a YOUR_APP_NAME
```

The second command creates a billable dedicated IPv4 address. If every player
has working IPv6, you can omit it and connect using the app's public IPv6
address.

The first deploy creates one 10 GB volume named `minecraft_data`. Do not scale
this app above one Machine: Minecraft world files are not safe for concurrent
writes, and Fly Volumes attach to one Machine.

## 4. Connect

Java Edition:

```text
YOUR_APP_NAME.fly.dev
```

Bedrock Edition:

```text
Address: YOUR_APP_NAME.fly.dev
Port: 19132
```

A cold start can take tens of seconds. The first connection may time out while
the Machine and Paper start; retry after checking:

```sh
fly status -a YOUR_APP_NAME
fly logs -a YOUR_APP_NAME
```

## Administration

Open the Paper console:

```sh
fly ssh console -a YOUR_APP_NAME -C "rcon-cli"
```

Useful console commands include `whitelist on`, `whitelist add PLAYER_NAME`,
`op PLAYER_NAME`, `save-all flush`, and `stop`.

Create an on-demand volume snapshot:

```sh
fly volumes list -a YOUR_APP_NAME
fly volumes snapshots create VOLUME_ID
```

Automatic snapshots are configured for 14-day retention. They are not a
replacement for tested off-platform backups.

## DigitalOcean Spaces backups

`backup-server-data.sh` creates a consistent restic backup of the worlds,
plugins, and server configuration in:

```text
s3:https://tor1.digitaloceanspaces.com/minecraft-gredell/minecraft-paper-server
```

The script disables saving, flushes the world, uploads directly from Fly,
re-enables saving, and retains seven daily Fly snapshots. Credentials are Fly
secrets and must not be committed to this repository.

The separate Fly app `minecraft-backup-trigger-007a5d` contains a 256 MB
scheduled Machine (`837057b7175738`). Once per approximate day, it wakes the
existing Minecraft Machine, runs the backup over Fly SSH, and exits. It has no
public service, volume, or Spaces credentials.

Fly anchors a daily schedule to its first run. This Machine was first started
overnight on October 15, 2026 around 3:34 AM Pacific, so later runs should stay
in the middle of the night. The time is approximate, not an exact clock. The
old DigitalOcean timer is disabled and is not involved in backups.

Run and inspect backups manually:

```sh
fly ssh console -a minecraft-on-demand-007a5d \
  -C "/usr/local/bin/backup-server-data"
fly ssh console -a minecraft-on-demand-007a5d \
  -C "restic snapshots --host minecraft-on-demand-007a5d --tag minecraft-fly"
```

Restore into a temporary directory first; do not overwrite a running world:

```sh
fly ssh console -a minecraft-on-demand-007a5d \
  -C "restic restore latest --host minecraft-on-demand-007a5d \
  --tag minecraft-fly --target /data/restore"
```

## Migrated server data

The server uses the migrated worlds and configuration from the previous host.
Geyser, Floodgate, and ViaVersion provide Bedrock cross-play.

Rollback copies are retained in two places:

- the original server and `/root/minecraft-fly-migration.tar.gz` on the old host;
- `/data/pre-import-backup-20261012T041913Z` on the Fly Volume.

## Change the idle timeout or server version

`AUTOSTOP_TIMEOUT_EST` is seconds after the last player disconnects.
`AUTOSTOP_TIMEOUT_INIT` is seconds allowed for someone to join after startup.

The server is pinned to Minecraft `1.21.11`, Paper build `38`. Before changing
`VERSION` or `PAPER_BUILD` under `[env]` in `fly.toml`, take a snapshot.
Minecraft world upgrades generally cannot be reversed.

After configuration changes:

```sh
fly deploy --ha=false -a YOUR_APP_NAME
```

## On-demand caveats

- Any incoming connection can wake a public server, including status pings and
  internet scanners. A whitelist controls joining but not waking.
- Fly Volumes are tied to one physical host and do not replicate automatically.
- The first client may need to reconnect after a cold start.
- Controlled Fly shutdowns allow up to 120 seconds for the server to save.

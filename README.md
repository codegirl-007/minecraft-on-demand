# On-demand Minecraft on Fly.io

Paper 1.21.11 with Java and Bedrock cross-play. The machine is **stopped until
someone connects**, then it saves and powers itself off after 15 minutes empty.

This is the config we run. Clone it, change the app name, deploy.

## How it wakes

Nothing custom is listening for players. Fly’s edge proxy already owns the
public ports, even while the machine is off:

| Players | Port | Protocol |
| --- | --- | --- |
| Java Edition | 25565 | TCP |
| Bedrock Edition | 19132 | UDP |

`auto_start_machines = true` starts the Fly Machine when a packet hits either
port. Paper and Geyser bind those same ports **inside** the VM after boot.

Fly autostop is **off**. A game server has to `save` before it dies. The itzg
image does that instead (`ENABLE_AUTOSTOP=TRUE`): 15 minutes with nobody online,
then a clean Minecraft stop. Restart policy is `on-failure`, so a clean idle
exit stays asleep.

A whitelist blocks joining, not waking. Server-list pings and scanners can start
the machine.

Bedrock needs a **dedicated IPv4** ($2/mo). Fly cannot do public UDP on shared
IPv4 or IPv6. Geyser must bind `fly-global-services`, not `0.0.0.0`.

## Cost

The machine is `performance-1x` with 8 GB RAM (6 GB heap) in `sjc`. CPU and RAM
bill only while it runs. You still pay for:

- 10 GB volume
- stopped machine rootfs
- volume snapshots (first 10 GB/month free)
- dedicated IPv4

Typical month is cheap if it only runs when people play. Always-on is ~$80+.

## Setup

### 1. Install flyctl and sign in

https://fly.io/docs/flyctl/install/

```sh
fly auth login
```

### 2. Name the app

Fly app names are global. Edit `app` and `primary_region` in `fly.toml`. Pick a
region close to the players:

```sh
fly platform regions
```

### 3. Create, give it a public IPv4, deploy

```sh
fly apps create YOUR_APP_NAME
fly ips allocate-v4 -a YOUR_APP_NAME
fly deploy --ha=false
```

`allocate-v4` is the billable dedicated IPv4 Bedrock needs. Skip it only if
every player has working IPv6 and you will connect over IPv6.

The first deploy creates one 10 GB volume, `minecraft_data`. **Do not scale
above one machine.** Minecraft worlds are not safe for concurrent writes, and a
Fly volume attaches to one machine.

### 4. Connect

Java:

```text
YOUR_APP_NAME.fly.dev
```

Bedrock:

```text
Address: YOUR_APP_NAME.fly.dev
Port: 19132
```

Cold start takes tens of seconds. The first join often times out while Paper
boots; retry, or watch:

```sh
fly status -a YOUR_APP_NAME
fly logs -a YOUR_APP_NAME
```

### 5. Bedrock bind (required)

On first boot Geyser writes `plugins/Geyser-Spigot/config.yml` with
`address: 0.0.0.0`. Fly UDP will not reach that. SSH in after the first start
and set:

```yaml
bedrock:
  address: fly-global-services
```

Then `fly machine stop` (or let autostop fire) and join again.

The image ships **Geyser** and **ViaVersion**. **Floodgate** is what lets
Bedrock players in without a Java account. This live server got Floodgate from
the migrated world. For a fresh server, drop `floodgate-spigot.jar` into
`/plugins` (or add it to the Dockerfile) and restart.

### 6. Lock it down

```sh
fly ssh console -a YOUR_APP_NAME -C "rcon-cli"
```

Then: `whitelist on`, `whitelist add PLAYER`, `op PLAYER` as needed.

## Import an existing world (optional)

`import-server-data.sh` runs once at boot if this file exists:

```text
/data/import/server-data.tar.gz
```

It checks a SHA-256, requires `world/level.dat`, `server.properties`, Geyser,
and Floodgate, patches Geyser to `fly-global-services`, and moves the old Fly
data aside.

For your own world:

1. Tar the server directory (worlds, plugins, `server.properties`, etc.).
2. Put the checksum of **your** archive into `import-server-data.sh`.
3. Copy the tar onto the volume, for example with `fly sftp` or `fly ssh sftp`.
4. Restart the machine so `PRE_START_SCRIPT` runs.

With no archive present, the script is a no-op and itzg generates a new world.

## Nightly restic backups (optional)

`backup-server-data.sh` lives **on the Minecraft machine**. It RCON `save-off`,
flushes, uploads with restic, then `save-on`. Set these as secrets on the
**Minecraft** app (never commit them):

```sh
fly secrets set -a YOUR_APP_NAME \
  RESTIC_REPOSITORY='s3:https://REGION.digitaloceanspaces.com/BUCKET/path' \
  RESTIC_PASSWORD='...' \
  AWS_ACCESS_KEY_ID='...' \
  AWS_SECRET_ACCESS_KEY='...'
```

`RCON_PASSWORD` is already set by the itzg image. Point `RESTIC_REPOSITORY` at
S3-compatible storage (this install uses DigitalOcean Spaces).

A second tiny Fly app wakes the server on a daily schedule, SSHs in, runs the
backup, and exits. It has no volume and no Spaces credentials.

```sh
fly apps create YOUR_BACKUP_APP
fly secrets set -a YOUR_BACKUP_APP \
  FLY_API_TOKEN="$(fly tokens create deploy -a YOUR_APP_NAME)" \
  TARGET_APP=YOUR_APP_NAME \
  TARGET_MACHINE="$(fly machines list -a YOUR_APP_NAME --json | jq -r '.[0].id')"
```

From the repo root:

```sh
fly deploy -a YOUR_BACKUP_APP --ha=false \
  --dockerfile backup-trigger/Dockerfile
```

Then attach a daily schedule to that machine (Fly anchors the clock to the
**first start**, not an exact crontab):

```sh
fly machines list -a YOUR_BACKUP_APP
fly machine update MACHINE_ID -a YOUR_BACKUP_APP --schedule daily
```

Start it once at the time of day you want backups (overnight, usually). Later
runs stay near that time.

Manual backup / list / restore (restore into a temp dir, never over a live
world):

```sh
fly ssh console -a YOUR_APP_NAME -C "/usr/local/bin/backup-server-data"
fly ssh console -a YOUR_APP_NAME \
  -C "restic snapshots --host YOUR_APP_NAME --tag minecraft-fly"
fly ssh console -a YOUR_APP_NAME \
  -C "restic restore latest --host YOUR_APP_NAME --tag minecraft-fly --target /data/restore"
```

The backup script currently tags snapshots with host `minecraft-on-demand-007a5d`.
Change those `--host` flags in `backup-server-data.sh` if your app name differs.

## Version and idle timeout

Pinned: Minecraft `1.21.11`, Paper build `38`. Snapshot the volume before
changing `VERSION` or `PAPER_BUILD`. World upgrades generally cannot be reversed.

| Env | Meaning |
| --- | --- |
| `AUTOSTOP_TIMEOUT_INIT` | Seconds to wait for the first join after boot (900) |
| `AUTOSTOP_TIMEOUT_EST` | Seconds after the last player leaves (900) |

```sh
fly deploy --ha=false
```

## Layout

| File | Role |
| --- | --- |
| `fly.toml` | Machine size, volume, TCP 25565, UDP 19132, autostart |
| `Dockerfile` | itzg Paper, Geyser, ViaVersion, restic |
| `import-server-data.sh` | One-time world import + Geyser UDP bind |
| `backup-server-data.sh` | RCON flush + restic |
| `backup-trigger/` | Daily machine that wakes the server and runs the backup |

## Caveats

- Any packet on 25565/19132 can wake a public server.
- Fly volumes live on one host; they do not replicate.
- The first client after a nap may need to reconnect.
- Fly gives the process 120 seconds (`kill_timeout`) to save on a controlled stop.

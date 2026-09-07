# Database Migration: anno-app-opi3bp-01 → anno-db-oci-01 (OCI VPS)

**Date**: 2026-09-07
**Status**: 🟡 In progress

---

## What's moving and why

PostgreSQL, MariaDB, Redis, and MinIO move off the application server
(`anno-app-opi3bp-01`, a 2 GB Orange Pi 3B+ on a microSD card) onto a new
node, `anno-db-oci-01`, an Oracle Cloud Infrastructure VPS. The app
containers (n8n, twenty-crm, monica, tandoor, peekaping, etc.) stay put on
the Pi and reach the DBs remotely over Tailscale.

This retires two DB stacks at once:
- `docker/application-server/docker-compose.db.yml` (postgres, mariadb, redis on the `annogrid` network)
- `docker/application-server/core-data/` (postgres, mariadb, redis, minio on `core-data_default`)

Both compose files are now intentional no-ops (`services: {}`) — see the
comment block at the top of each. `anno-db-oci-01/docker-compose.yml`
replaces them with one consolidated stack.

Repo changes already made as part of this migration:
- `nodes/anno-db-oci-01/` — new node (compose file, `.env.example`, README)
- `docker/application-server/docker-compose.app.yml` / `docker-compose.mon.yml` —
  DB hostnames changed from local container names (`postgres`, `mariadb`) to
  `${ANNOGRID_DB_HOST}`
- `n8n/`, `twenty-personal-crm/`, `peekaping/` compose files — moved off the
  now-retired `core-data_default` network onto the shared `annogrid` network;
  DB host vars now point at the OCI node
- `docs/architecture/nodes-inventory.md` — new node entry

What's **not** done automatically: provisioning the actual OCI VPS, moving
the real data, rotating secrets, and redeploying each stack. That's this
document.

---

## Pre-migration checklist

- [ ] OCI account with a compartment/VCN ready
- [ ] Tailscale account (same tailnet as the rest of AnnoGrid)
- [ ] Confirmed which DB stack was actually live — check
      `MANIFEST.txt` from `docker/application-server/restore/extract-sdcard-data.sh`
      (or `docker volume ls` on the live Pi) to see whether
      `docker-compose.db.yml`'s volumes or `core-data/`'s volumes had real
      data. Likely only one did — n8n's compose file comments suggest
      `core-data` was the live one.
- [ ] A maintenance window — app containers will be down briefly during cutover
- [ ] Somewhere to stash a full backup before touching anything (see Step 1)

---

## Step 1 — Back up before you touch anything

If the Pi is still running:
```bash
ssh pi@anno-app-opi3bp-01.local
docker exec annogrid-postgres pg_dumpall -U "$POSTGRES_USER" | gzip > ~/postgres_pre_migration_$(date +%F).sql.gz
docker exec annogrid-mariadb sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' | gzip > ~/mariadb_pre_migration_$(date +%F).sql.gz
docker cp annogrid-redis:/data/dump.rdb ~/redis_pre_migration_$(date +%F).rdb
scp ~/*_pre_migration_* you@your-workstation:/mnt/hdd/sdcard-backups/pre-migration/
```

If you're working from the recovered SD card instead (Pi is dead/replaced),
you already have this — it's `app-server-data_<date>/docker_volumes/*.tar.gz`
from the extraction steps in `RESTORE.md`. Either way, don't proceed without
a copy that isn't on the box you're about to change.

---

## Step 2 — Provision the OCI VPS

1. Create a Compute instance: Ubuntu 22.04+, ≥2 OCPU / 4 GB RAM, a Block
   Volume sized for your data + growth (check dump/tarball sizes from Step 1).
2. **Lock down the Security List/NSG immediately** — allow only SSH (22) and
   Tailscale (UDP 41641). Do not open 5432/3306/6379/9000/9001 publicly;
   `anno-db-oci-01/docker-compose.yml` binds those to the Tailscale IP only,
   but the cloud firewall is your second layer, not optional.
3. Install Docker + Tailscale, join the tailnet:
   ```bash
   ssh ubuntu@<oci-public-ip>
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker ubuntu
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   tailscale ip -4   # note this Tailscale IP
   ```
4. After this step you can (and should) stop using the public IP entirely —
   everything from here on happens over Tailscale.

Full detail: [`nodes/anno-db-oci-01/README.md`](../../nodes/anno-db-oci-01/README.md).

---

## Step 3 — Deploy the empty DB stack on OCI

```bash
# on anno-db-oci-01
cd /path/to/annogrid/nodes/anno-db-oci-01
cp .env.example .env
# fill in: TAILSCALE_IP (from step 2) + generate FRESH credentials —
# do not reuse the old ones, see "Secrets" below
docker compose up -d
docker compose ps   # all healthy before continuing
```

---

## Step 4 — Move the data in

**PostgreSQL** (from the pre-migration dump, over Tailscale):
```bash
cat postgres_pre_migration_*.sql.gz | gunzip | \
  psql "postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@<oci-tailscale-ip>:5432/postgres"
```

**MariaDB**:
```bash
cat mariadb_pre_migration_*.sql.gz | gunzip | \
  mysql -h <oci-tailscale-ip> -u root -p"$MYSQL_ROOT_PASSWORD"
```

**Redis** (dump.rdb approach — simplest for a one-time cutover):
```bash
docker compose -f nodes/anno-db-oci-01/docker-compose.yml stop redis
scp redis_pre_migration_*.rdb ubuntu@<oci-tailscale-ip>:/tmp/dump.rdb
ssh ubuntu@<oci-tailscale-ip> \
  'docker run --rm -v annogrid_redis_data:/data -v /tmp:/backup alpine cp /backup/dump.rdb /data/dump.rdb'
docker compose -f nodes/anno-db-oci-01/docker-compose.yml start redis
```

**MinIO** (if `core-data`'s minio volume actually had data — check the
extraction MANIFEST first):
```bash
# on your workstation, with the mc client
mc alias set old-minio http://<recovered-minio-endpoint> "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc alias set new-minio http://<oci-tailscale-ip>:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mirror old-minio/ new-minio/
```

If you're restoring from the SD-card extraction instead of a live pg_dump,
use `docker/application-server/restore/restore-to-new-host.sh` against
`nodes/anno-db-oci-01` first to get the raw volumes in place, then still take
a fresh `pg_dumpall`/`mariadb-dump` on the new host and treat *that* as your
real baseline going forward (see `RESTORE.md` §5 — raw volumes from a pulled
card are only crash-consistent).

---

## Step 5 — Secrets: rotate, except where you can't

Per `RESTORE.md` §4, applied here too:

- **Rotate**: `POSTGRES_PASSWORD`, `MYSQL_*_PASSWORD`, `REDIS_PASSWORD`,
  `MINIO_ROOT_PASSWORD`. Set the new values in `nodes/anno-db-oci-01/.env`,
  then update the actual DB users after restore (`ALTER USER ... PASSWORD`,
  `redis-cli CONFIG SET requirepass`, `mc admin user ...`).
- **Do not rotate**: `N8N_ENCRYPTION_KEY`, `APP_SECRET` (twenty-crm),
  `MONICA_APP_KEY` — these decrypt data already in the DB. Copy them
  unchanged into the app-server `.env` files.

---

## Step 6 — Cut the app layer over

On `anno-app-opi3bp-01`, update each stack's `.env` to point at
`anno-db-oci-01.<your-tailnet>.ts.net` (or its Tailscale IP) instead of the
old local container names, using the new rotated passwords from Step 5:

| Stack | File | Vars to update |
|---|---|---|
| core stack | `docker/application-server/.env` | `ANNOGRID_DB_HOST`, `POSTGRES_*`, `MYSQL_*` |
| n8n | `docker/application-server/n8n/.env` | `DB_POSTGRESDB_HOST`, `DB_POSTGRESDB_PASSWORD` |
| twenty-crm | `docker/application-server/twenty-personal-crm/.env` | `PG_DATABASE_URL`, `REDIS_URL` |
| peekaping | `docker/application-server/peekaping/.env` | `PEEKAPING_DB_HOST`, `REDIS_HOST`, `REDIS_PASS` |

Then redeploy each:
```bash
cd docker/application-server
docker compose -f docker-compose.app.yml up -d
docker compose -f docker-compose.mon.yml up -d
cd n8n && docker compose up -d
cd ../twenty-personal-crm && docker compose up -d
cd ../peekaping && docker compose up -d
```

`docker-compose.db.yml` and `core-data/docker-compose.yml` stay as their
no-op stubs — nothing to run there anymore.

---

## Step 7 — Verify

```bash
# From anno-app-opi3bp-01, confirm connectivity
psql -h anno-db-oci-01.<your-tailnet>.ts.net -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\dt'
redis-cli -h anno-db-oci-01.<your-tailnet>.ts.net -a "$REDIS_PASSWORD" ping

# Check each app actually works
docker compose ps            # in each stack directory — all healthy
# Then hit each service's UI: n8n workflows list, twenty-crm records,
# monica contacts, tandoor recipes — confirm real data shows up, not empty state
```

---

## Step 8 — Decommission the old volumes (only after Step 7 is fully green)

On `anno-app-opi3bp-01`, once the new DB has been running clean for a while:
```bash
docker volume rm annogrid_postgres_data annogrid_mariadb_data annogrid_redis_data
docker volume rm core-data_postgres_data core-data_mariadb_data core-data_redis_data core-data_minio_data 2>/dev/null
```
Don't rush this — keep the old volumes (and the SD card image from
`RESTORE.md`) until you're confident the new node is solid. Storage on the
Pi's microSD is the whole reason for this migration, not something to reclaim
in a hurry.

---

## Rollback

If Step 6/7 goes wrong: revert each stack's `.env` to point back at the old
local container names, redeploy `docker-compose.db.yml`/`core-data/` by
restoring their original service definitions from git history
(`git log -- docker/application-server/docker-compose.db.yml`), and bring the
local DB containers back up. The old volumes are untouched until Step 8, so
this is safe as long as Step 8 hasn't run yet.

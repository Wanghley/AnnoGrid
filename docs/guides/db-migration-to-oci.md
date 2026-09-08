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

This retires two local DB stacks on the Pi:
- `docker/application-server/docker-compose.db.yml` (postgres, mariadb, redis on the `shared` network) — now a no-op stub, permanently retired.
- `docker/core-data/`'s **pre-migration** local deployment (postgres, mariadb, redis, minio on `core-data_default`)

> **Note on `docker/core-data/`**: this path briefly held a no-op stub right
> after the migration started, then got its real compose stack back — it now
> holds the **new consolidated stack** (`postgres_data`, `mariadb_data`,
> `redis_data`, `minio_data` volumes, bare names, no prefix), just deployed
> on `anno-db-oci-01` instead of the Pi. Same repo path, different physical
> host. See [`docker/core-data/README.md`](../../docker/core-data/README.md).

Repo changes already made as part of this migration:
- `docker/core-data/` — holds the consolidated stack (compose file, `.env.example`, README), deployed on `anno-db-oci-01`
- `nodes/anno-db-oci-01/README.md` — node-level pointer (SSH access, hardware) to `docker/core-data/`
- `docker/application-server/docker-compose.app.yml` / `docker-compose.mon.yml` —
  DB hostnames changed from local container names (`postgres`, `mariadb`) to
  `${ANNOGRID_DB_HOST}`
- `docker/n8n/`, `docker/twenty-personal-crm/`, `docker/peekaping/` compose
  files — moved off the now-retired `core-data_default` network onto the
  `shared` docker network; DB host vars now point at the OCI node
- `docs/architecture/nodes-inventory.md` — new node entry
- Separately, `docker/` was flattened: `core-data/`, `n8n/`, `tandoor/`,
  `twenty-personal-crm/`, `obsidian/`, `homarr/`, `portainer/`, `peekaping/`,
  `homepage/` are top-level siblings under `docker/`, not nested under
  `application-server/`; `docker/canary`, `docker/general`,
  `docker/monitoring`, `docker/wppconnect` moved under `docker/shared/`. See
  [`docker/README.md`](../../docker/README.md).

What's **not** done automatically: provisioning the actual OCI VPS, moving
the real data, rotating secrets, and redeploying each stack. That's this
document.

---

## Pre-migration checklist

- [ ] OCI account with a compartment/VCN ready
- [ ] Tailscale account (same tailnet as the rest of AnnoGrid)
- [ ] Confirmed which DB stack was actually live — check
      `MANIFEST.txt` from `docker/restore/extract-sdcard-data.sh`
      (or `docker volume ls` on the live Pi) to see whether
      `docker-compose.db.yml`'s volumes or `core-data`'s volumes had real
      data. Confirmed: the Pi had `core-data_postgres_data`,
      `core-data_mariadb_data`, `core-data_redis_data`, `core-data_minio_data`
      — no `annogrid_*` volumes existed, so `docker-compose.db.yml`'s local
      stack was never actually populated.
- [ ] A maintenance window — app containers will be down briefly during cutover
- [ ] Somewhere to stash a full backup before touching anything (see Step 1)

---

## Step 1 — Back up before you touch anything

If the Pi is still running:
```bash
ssh pi@anno-app-opi3bp-01.local
docker exec core-data-postgres pg_dumpall -U "$POSTGRES_USER" | gzip > ~/postgres_pre_migration_$(date +%F).sql.gz
docker exec core-data-mariadb sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' | gzip > ~/mariadb_pre_migration_$(date +%F).sql.gz
docker cp core-data-redis:/data/dump.rdb ~/redis_pre_migration_$(date +%F).rdb
scp ~/*_pre_migration_* you@your-workstation:/mnt/hdd/sdcard-backups/pre-migration/
```

If you're working from the recovered SD card instead (Pi is dead/replaced),
you already have this — the four `core-data_*` volume tarballs pulled
straight off the mounted card (see `RESTORE.md`), plus check
`postgres_backup` / `mariadb_backup` volumes if present — they may already
hold logical dumps, which are preferable to a raw volume copy. Either way,
don't proceed without a copy that isn't on the box you're about to change.

---

## Step 2 — Provision the OCI VPS

1. Create a Compute instance: Ubuntu 22.04+, ≥2 OCPU / 4 GB RAM, a Block
   Volume sized for your data + growth (check dump/tarball sizes from Step 1).
2. **Lock down the Security List/NSG immediately** — allow only SSH (22) and
   Tailscale (UDP 41641). Do not open 5432/3306/6379/9000/9001 publicly;
   `docker/core-data/docker-compose.yml` binds those to the Tailscale IP
   only, but the cloud firewall is your second layer, not optional.
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

Full detail: [`docker/core-data/README.md`](../../docker/core-data/README.md).

---

## Step 3 — Deploy the empty DB stack on OCI

Copy `docker/core-data/` onto the VPS (e.g. `scp -r` from your workstation,
or `git clone` the repo), then:

```bash
# on anno-db-oci-01
cd ~/annogrid/docker/core-data   # wherever you copied it to
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
docker compose -f docker/core-data/docker-compose.yml stop redis
scp redis_pre_migration_*.rdb ubuntu@<oci-tailscale-ip>:/tmp/dump.rdb
ssh ubuntu@<oci-tailscale-ip> \
  'docker run --rm -v redis_data:/data -v /tmp:/backup alpine cp /backup/dump.rdb /data/dump.rdb'
docker compose -f docker/core-data/docker-compose.yml start redis
```

**MinIO** (if the `core-data_minio_data` volume actually had data — check the
extraction MANIFEST first):
```bash
# on your workstation, with the mc client
mc alias set old-minio http://<recovered-minio-endpoint> "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc alias set new-minio http://<oci-tailscale-ip>:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mirror old-minio/ new-minio/
```

If you're restoring from the SD-card extraction instead of a live pg_dump:
the recovered tarballs are named `core-data_postgres_data.tar.gz` etc, and
the new volumes are bare-named (`postgres_data`, `mariadb_data`,
`redis_data`, `minio_data` — no prefix). Create each volume and untar
directly (no renaming needed beyond dropping the `core-data_` prefix):
```bash
docker volume create postgres_data
docker run --rm -v postgres_data:/target -v /tmp/core-data_postgres_data.tar.gz:/backup.tar.gz:ro \
  alpine sh -c "tar xzf /backup.tar.gz -C /target"
# repeat for mariadb_data, redis_data, minio_data
```
Then still take a fresh `pg_dumpall`/`mariadb-dump` on the new host and treat
*that* as your real baseline going forward (see `RESTORE.md` §5 — raw
volumes from a pulled card are only crash-consistent).

---

## Step 5 — Secrets: rotate, except where you can't

Per `RESTORE.md` §4, applied here too:

- **Rotate**: `POSTGRES_PASSWORD`, `MYSQL_*_PASSWORD`, `REDIS_PASSWORD`,
  `MINIO_ROOT_PASSWORD`. Set the new values in `docker/core-data/.env` (on
  the VPS), then update the actual DB users after restore (`ALTER USER ...
  PASSWORD`, `redis-cli CONFIG SET requirepass`, `mc admin user ...`).
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
| n8n | `docker/n8n/.env` | `DB_POSTGRESDB_HOST`, `DB_POSTGRESDB_PASSWORD` |
| twenty-crm | `docker/twenty-personal-crm/.env` | `PG_DATABASE_URL`, `REDIS_URL` |
| peekaping | `docker/peekaping/.env` | `PEEKAPING_DB_HOST`, `REDIS_HOST`, `REDIS_PASS` |

Then redeploy each:
```bash
cd docker/application-server
docker compose -f docker-compose.app.yml up -d
docker compose -f docker-compose.mon.yml up -d
cd ../n8n && docker compose up -d
cd ../twenty-personal-crm && docker compose up -d
cd ../peekaping && docker compose up -d
```

`application-server/docker-compose.db.yml` stays a no-op stub — nothing to
run there anymore. `docker/core-data/` is no longer run here at all; it now
runs exclusively on `anno-db-oci-01`.

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
docker volume rm core-data_postgres_data core-data_mariadb_data core-data_redis_data core-data_minio_data
```
Don't rush this — keep the old volumes (and the SD card image from
`RESTORE.md`) until you're confident the new node is solid. Storage on the
Pi's microSD is the whole reason for this migration, not something to reclaim
in a hurry.

---

## Rollback

If Step 6/7 goes wrong: revert each stack's `.env` to point back at the old
local container names, redeploy `docker/core-data/` locally on the Pi by
restoring its pre-migration compose file from git history
(`git log -- docker/core-data/docker-compose.yml`), and bring the local DB
containers back up. The old volumes are untouched until Step 8, so this is
safe as long as Step 8 hasn't run yet.

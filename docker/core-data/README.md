# core-data — Centralized Database Server

**What**: PostgreSQL, MariaDB, Redis, MinIO for every AnnoGrid app stack
**Where it runs**: [`anno-db-oci-01`](../../nodes/anno-db-oci-01/README.md) (OCI VPS)
**Status**: 🟡 Provisioning — see [`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)

---

## Why this exists here

Postgres/MariaDB/Redis/MinIO used to run as local containers on
`anno-app-opi3bp-01` (two separate stacks: `../application-server/docker-compose.db.yml`
and this stack's own pre-2026-09-07 local deployment). Both are retired in
favor of running this stack on a dedicated node so the app server isn't also
carrying DB I/O on a 2 GB Orange Pi with a microSD card as its only disk.

Every AnnoGrid app service reaches this stack **only over Tailscale** — no
database port is ever exposed to the public internet.

---

## Quick Start

```bash
# SSH into anno-db-oci-01
ssh ubuntu@anno-db-oci-01.<your-tailnet>.ts.net

# Deploy
cd /path/to/annogrid/docker/core-data
cp .env.example .env   # fill in real secrets — see below
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

---

## First-Time Setup

1. **Provision the OCI instance.** Ubuntu 22.04+, at minimum 2 OCPU / 4 GB RAM
   (Postgres + MariaDB + Redis + MinIO together want headroom — the Orange Pi
   they're replacing only had 2 GB total). Attach a Block Volume sized for
   your actual data (check `MANIFEST.txt` from the SD-card extraction for
   current volume sizes) plus growth room.

2. **Lock down the OCI Security List / NSG before anything else.** Only allow:
   - SSH (22) from your admin IP or Tailscale
   - Tailscale UDP (41641) if not otherwise reachable

   Do **not** open 5432, 3306, 6379, 9000, or 9001 — this compose file binds
   all of these to the Tailscale IP only, but a permissive OCI Security List
   is a second layer you don't want to skip.

3. **Install Docker + Tailscale:**
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker ubuntu
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   tailscale ip -4    # note this — goes in .env as TAILSCALE_IP
   ```

4. **Deploy:**
   ```bash
   cp .env.example .env
   # edit .env: TAILSCALE_IP + all DB credentials (generate fresh ones —
   # don't reuse anything recovered from the SD card, see ../RESTORE.md §4)
   docker compose up -d
   ```

5. **Restore data** — see [`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)
   for the full pg_dump/mysqldump/redis/minio migration procedure using the
   SD-card extraction produced by [`../restore/extract-sdcard-data.sh`](../restore/extract-sdcard-data.sh).

6. **Point every app stack at this host** — set `ANNOGRID_DB_HOST` /
   `DB_POSTGRESDB_HOST` / `PG_DATABASE_URL` / `PEEKAPING_DB_HOST` etc. in
   `../application-server/.env` and each standalone stack's `.env`
   (`../n8n/.env`, `../twenty-personal-crm/.env`, `../peekaping/.env`) to
   `anno-db-oci-01.<your-tailnet>.ts.net`, then redeploy those stacks.

---

## Services

| Service | Port (Tailscale-only) | Data |
|---|---|---|
| postgres | 5432 | `postgres_data` |
| mariadb | 3306 | `mariadb_data` |
| redis | 6379 | `redis_data` |
| minio | 9000 (API), 9001 (console) | `minio_data` |
| node-exporter | 9100 | — (metrics only) |

---

## Backups

This stack is the **source of truth** for all AnnoGrid relational/cache/object
data. Back it up like it matters:

```bash
docker exec core-data-postgres pg_dumpall -U "$POSTGRES_USER" | gzip > /backup/postgres_$(date +%F).sql.gz
docker exec core-data-mariadb sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' | gzip > /backup/mariadb_$(date +%F).sql.gz
```

Logical dumps are preferred over raw volume copies — see
[`../RESTORE.md`](../RESTORE.md) §5. Ship these off-box (to
`anno-nas-rpi3bp-01` and/or OCI Object Storage) on a schedule — don't let the
only DB backups live on the same disk as the DB.

---

## Monitoring

**Metrics**: `http://<tailscale-ip>:9100/metrics`
**Prometheus scrape target**: `anno-db-oci-01:9100`, plus the existing
`postgres-exporter` / `mysqld-exporter` in
`../application-server/docker-compose.mon.yml` (already pointed at
`${ANNOGRID_DB_HOST}`).

---

## Troubleshooting

```bash
# Logs
docker compose logs -f postgres
docker compose logs -f mariadb

# Connectivity check from an app-server node
psql -h anno-db-oci-01.<your-tailnet>.ts.net -U "$POSTGRES_USER" -d "$POSTGRES_DB"
redis-cli -h anno-db-oci-01.<your-tailnet>.ts.net -a "$REDIS_PASSWORD" ping

# Disk space (Block Volume)
df -h
```

---

**Node details**: [`../../nodes/anno-db-oci-01/README.md`](../../nodes/anno-db-oci-01/README.md)
**Migration steps**: [`../../docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)

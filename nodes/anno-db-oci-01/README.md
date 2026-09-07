# anno-db-oci-01: Database Server Node

**Hardware**: Oracle Cloud Infrastructure VPS
**Role**: Centralized PostgreSQL, MariaDB, Redis, MinIO for all AnnoGrid app stacks
**Status**: 🟡 Provisioning — see [`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)

---

## Why this node exists

Postgres/MariaDB/Redis/MinIO used to run as local containers on
`anno-app-opi3bp-01` (two separate stacks: `docker/application-server/docker-compose.db.yml`
and `docker/core-data/`). Both are now retired in favor of
this single node so the app server isn't also carrying DB I/O on a 2 GB
Orange Pi with a microSD card as its only disk.

Every AnnoGrid app service reaches this node **only over Tailscale** — no
database port is ever exposed to the public internet.

---

## Quick Start

```bash
# SSH into the VPS
ssh ubuntu@anno-db-oci-01.<your-tailnet>.ts.net

# Deploy
cd /path/to/annogrid/nodes/anno-db-oci-01
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

   Do **not** open 5432, 3306, 6379, 9000, or 9001 — the compose file binds
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
   # don't reuse anything recovered from the SD card, see RESTORE.md §4)
   docker compose up -d
   ```

5. **Restore data** — see [`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)
   for the full pg_dump/mysqldump/redis/minio migration procedure using the
   SD-card extraction produced by `docker/restore/extract-sdcard-data.sh`.

6. **Point every app stack at this node** — set `ANNOGRID_DB_HOST` /
   `DB_POSTGRESDB_HOST` / `PG_DATABASE_URL` / `PEEKAPING_DB_HOST` etc. in
   `docker/application-server/.env` and each standalone stack's `.env`
   (`docker/n8n/.env`, `docker/twenty-personal-crm/.env`,
   `docker/peekaping/.env`) to this node's Tailscale IP or MagicDNS name
   (`anno-db-oci-01.<your-tailnet>.ts.net`), then redeploy those stacks.

---

## Services

| Service | Port (Tailscale-only) | Data |
|---|---|---|
| postgres | 5432 | `annogrid_postgres_data` |
| mariadb | 3306 | `annogrid_mariadb_data` |
| redis | 6379 | `annogrid_redis_data` |
| minio | 9000 (API), 9001 (console) | `annogrid_minio_data` |
| node-exporter | 9100 | — (metrics only) |

---

## Backups

This node is now the **source of truth** for all AnnoGrid relational/cache/object
data. Back it up like it matters:

```bash
# Logical dumps (preferred over raw volume copies — see RESTORE.md §5)
docker exec annogrid-postgres pg_dumpall -U "$POSTGRES_USER" | gzip > /backup/postgres_$(date +%F).sql.gz
docker exec annogrid-mariadb sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' | gzip > /backup/mariadb_$(date +%F).sql.gz
```

Ship these off-box (to `anno-nas-rpi3bp-01` and/or OCI Object Storage) on a
schedule — don't let the only DB backups live on the same disk as the DB.

---

## Monitoring

**Metrics**: `http://<tailscale-ip>:9100/metrics`
**Prometheus scrape target**: `anno-db-oci-01:9100`, plus the existing
`postgres-exporter` / `mysqld-exporter` in
`docker/application-server/docker-compose.mon.yml` (already pointed at
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

**For the full picture**: [`../../docs/architecture/nodes-inventory.md`](../../docs/architecture/nodes-inventory.md)
**Migration steps**: [`../../docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)

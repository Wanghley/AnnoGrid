# Application Server — Data Recovery & Restore

Node: **anno-app-opi3bp-01** (Orange Pi 3B+, Armbian, 64 GB microSD).
See [`docs/architecture/nodes-inventory.md`](../../docs/architecture/nodes-inventory.md) for hardware/network details.

This document covers recovering data **from a pulled SD card** and restoring it onto
a Docker host (the same board with a fresh card, or a temporary replacement). It
assumes you already have a raw image of the card (`.img`) and know how to
mount it read-only — see the general SD-card imaging steps earlier in this
conversation (`ddrescue` full image → `losetup -P` → `mount -o ro,noload`).

Nothing here restores secrets automatically. `.env` files and all volume data
are **gitignored** and only ever existed on the live server (and now, the SD
card) — the repo only holds the compose "recipes".

---

## 1. What's actually running on this node

Everything under this directory (`docker/application-server/`). Two layers:

**Core stack** (managed together via `setup.sh` / `manage.sh`, network `annogrid`):

| File | Services | Data |
|---|---|---|
| `docker-compose.db.yml` | postgres, mariadb, redis | `annogrid_postgres_data`, `annogrid_mariadb_data`, `annogrid_redis_data` (named volumes) + `configs/postgres`, `configs/mariadb` init scripts |
| `docker-compose.app.yml` | monica, n8n *(legacy — see note)*, jellyfin | `monica_data`, `n8n_data`, `jellyfin_config`, `jellyfin_cache` (named volumes) |
| `docker-compose.mon.yml` | node-exporter, cadvisor, postgres-exporter, mysqld-exporter | stateless (no persistent data of its own) |

**Standalone stacks** (each deployed independently, most on the shared `core-data_default` network):

| Directory | Service | Data location | Notes |
|---|---|---|---|
| `core-data/` | postgres, mariadb, redis, minio | `postgres_data`, `mariadb_data`, `mongo_data`, `redis_data`, `minio_data` (project-prefixed named volumes) | A **second**, separate DB stack from `docker-compose.db.yml` — confirm on the image which one is actually populated (see §2). |
| `n8n/` | n8n, n8n-runner | external volume `N8n-n8n_storage` → `/home/node/.n8n` | Current n8n deployment (DB lives in `core-data` postgres, not in this volume). `N8N_ENCRYPTION_KEY` in its `.env` is load-bearing — losing it makes all stored credentials unreadable. |
| `twenty-personal-crm/` | twenty-server, twenty-worker | bind mount `./data/storage` → `.local-storage` | DB/Redis in `core-data` stack. |
| `tandoor/` | web_recipes | volume `staticfiles` + bind mount `./mediafiles` | Recipe images/uploads are in `mediafiles`. |
| `obsidian/` | couchdb | bind mounts `./couchdb-data`, `./couchdb-etc` | Obsidian LiveSync backend. |
| `homarr/` | homarr | bind mount `./data` | Dashboard config. |
| `portainer/` | portainer | volume `portainer_data` | Low value — just UI state/settings, safe to skip if time-constrained. |
| `peekaping/` | gateway, web, api, migrate, producer, worker, ingester | none (stateless; DB in `core-data`) | Just needs `.env` restored. |
| `homepage/` | homepage | bind mounts `./config`, `./public` | Dashboard config, low priority. |

> ⚠️ **`n8n` and `postgres`/`mariadb` appear twice** (once in the core stack, once in
> `core-data/` and `n8n/`). Compose file comments ("Ties to your existing N8n
> volume", "Postgres and Redis live in the core-data stack") suggest `core-data/`
> + `n8n/` are the **live** deployment and `docker-compose.app.yml`'s n8n /
> `docker-compose.db.yml` may be legacy or partially superseded. Don't guess —
> the extraction script below reads real volume names off the card instead of
> trusting either compose file, so this gets resolved automatically in step 2.

---

## 2. Extract everything from the SD card image

With the card's rootfs partition already mounted read-only (per the earlier
imaging steps) at, e.g., `/mnt/rpi_root`:

```bash
cd docker/application-server/restore
sudo ./extract-sdcard-data.sh /mnt/rpi_root /path/to/backup/app-server-data
```

This will:
1. Locate the AnnoGrid checkout on the card (by finding `docker-compose.db.yml`).
2. Enumerate **every** Docker named volume actually present under
   `/var/lib/docker/volumes/` on the card (ground truth — not a guess from
   compose files) and tar each one up, auto-labeling it by keyword
   (postgres/mariadb/redis/mongo/minio/n8n/monica/jellyfin/etc.) in
   `MANIFEST.txt` so you can see which of the two DB stacks was actually live.
3. Pull every `.env` file found under the checkout (secrets — handle per §4).
4. Pull the gitignored bind-mount data dirs: `homarr/data`,
   `obsidian/couchdb-data` + `couchdb-etc`, `tandoor/mediafiles`,
   `twenty-personal-crm/data`, `homepage/config` + `public`.
5. Pull `configs/` (Postgres/MariaDB init scripts).

Read the generated `MANIFEST.txt` first — it tells you which volumes actually
had data (the dead volume declaration `mongodb_data` in `docker-compose.db.yml`,
for example, has no matching mongo service, so expect it empty/absent).

---

## 3. Restore onto a fresh host

Copy the extraction output (`app-server-data/`) onto the target machine, then:

```bash
cd docker/application-server/restore
./restore-to-new-host.sh /path/to/app-server-data
```

This recreates each Docker volume by its **original name** and untars the
backed-up contents into it — so as long as the target compose files reference
the same volume names, `docker compose up -d` will pick the data straight up.
It intentionally stops there; the rest is a manual, reviewed step:

1. **Recreate `.env` files.** For each `<stack>__.env` file under
   `env_files/`, rename it back to `.env` and place it next to that stack's
   `docker-compose.yml` (e.g. `env_files/n8n__.env` → `docker/application-server/n8n/.env`).
   Cross-check against each `.env.example` for the current expected variable set.
2. **Restore bind-mount data.** Copy folders from `bind_mounts/` back into
   place, e.g. `bind_mounts/homarr__data` → `docker/application-server/homarr/data`.
3. **Restore configs.** Copy `configs/` back to `docker/application-server/configs/`
   if you're restoring the `docker-compose.db.yml` stack.
4. **Bring services up in dependency order:**
   ```bash
   # Whichever DB stack MANIFEST.txt shows was actually populated:
   docker network create --subnet=172.20.0.0/24 annogrid   # if using docker-compose.db.yml
   docker compose -f docker-compose.db.yml up -d            # or: cd core-data && docker compose up -d
   sleep 5
   docker compose -f docker-compose.app.yml up -d
   docker compose -f docker-compose.mon.yml up -d

   # Standalone stacks depending on core-data_network:
   cd n8n && docker compose up -d
   cd ../twenty-personal-crm && docker compose up -d
   cd ../peekaping && docker compose up -d
   cd ../tandoor && docker compose up -d
   cd ../obsidian && docker compose up -d
   cd ../homarr && docker compose up -d
   cd ../portainer && docker compose up -d
   cd ../homepage && docker compose up -d
   ```
5. **Verify.** `docker compose ps` in each directory, then check each
   service's health endpoint / UI (ports are listed in each compose file).

---

## 4. Secrets — rotate, don't just reuse

The `n8n/.env.example` already flags this precedent: *"Rotate ALL of these —
the old ones were exposed in a public message."* Treat any secret recovered
from the card the same way by default:

- **Rotate:** all DB passwords (`POSTGRES_PASSWORD`, `MARIADB_*_PASSWORD`,
  `REDIS_PASSWORD`, `MINIO_ROOT_PASSWORD`), API keys, basic-auth creds.
  Update them in the new `.env` **and** in the restored database (`ALTER USER
  ... PASSWORD`, `redis-cli CONFIG SET requirepass`, etc.) after the DB
  container is up.
- **Do NOT rotate — must be restored byte-for-byte or data becomes unreadable:**
  - `N8N_ENCRYPTION_KEY` (n8n) — decrypts stored credentials/workflows.
  - `APP_SECRET` (twenty-crm) — JWT signing + field-level encryption.
  - `MONICA_APP_KEY` — Laravel app key, same deal.
  - `N8N_RUNNERS_AUTH_TOKEN` — must match between `n8n` and `n8n-runner`, but
    is fine to rotate as long as you update both sides together.

---

## 5. Database integrity note

Because the card was pulled rather than gracefully shut down, `postgres_data`
/ `mariadb_data` volumes are a **crash-consistent** copy, not a clean backup.
Postgres/MariaDB normally recover fine from this via WAL/redo-log replay on
first start, but for anything you can't afford to lose, prefer a logical dump
once the restored DB container is up and healthy, rather than trusting the
raw volume long-term:

```bash
docker exec annogrid-postgres pg_dumpall -U "$POSTGRES_USER" > postgres_full_dump.sql
docker exec annogrid-mariadb sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' > mariadb_full_dump.sql
```

Keep these dumps alongside the volume tarballs going forward as your actual
recovery point, not just the raw `/var/lib/docker/volumes` copy.

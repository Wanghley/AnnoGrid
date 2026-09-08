# anno-app-opi3bp-01: Application Server Node

**Hardware**: Orange Pi 3B+
**Role**: Run user-facing applications and web services
**Status**: 🟢 Active

---

## What's deployed here

This node runs the following stacks from [`../../docker/`](../../docker/README.md).
Each is deployed independently — there's no single `docker-compose.yml` for
"this node"; see each linked directory for its own `.env.example` and deploy
instructions.

| Stack | What it is |
|---|---|
| [`docker/application-server/`](../../docker/application-server/) | Core stack: monica, jellyfin, node-exporter/cadvisor/exporters (`docker-compose.app.yml` + `docker-compose.mon.yml`); `docker-compose.db.yml` is a retired no-op |
| [`docker/n8n/`](../../docker/n8n/) | Workflow automation |
| [`docker/tandoor/`](../../docker/tandoor/) | Recipe manager |
| [`docker/twenty-personal-crm/`](../../docker/twenty-personal-crm/) | CRM |
| [`docker/homarr/`](../../docker/homarr/) | Dashboard |
| [`docker/portainer/`](../../docker/portainer/) | Docker management UI |
| [`docker/peekaping/`](../../docker/peekaping/) | Uptime monitoring |
| [`docker/homepage/`](../../docker/homepage/) | Dashboard (homepage.sh cron + stats.json) |

**Databases**: PostgreSQL, MariaDB, Redis, CouchDB, and MinIO used to run
locally here (`application-server/docker-compose.db.yml`, now a retired
no-op; `docker/core-data/`'s own pre-migration local deployment; and
`docker/obsidian/`'s local couchdb, retired 2026-09-08). None of these run
on this node anymore — `docker/core-data/` now holds all of them,
exclusively on [`anno-db-oci-01`](../anno-db-oci-01/README.md); see
[`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md).
Every stack above reaches that node's DBs over Tailscale.

---

## Quick Start

```bash
# SSH into node
ssh pi@anno-app-opi3bp-01.local
cd /path/to/annogrid

# Deploy the core stack
cd docker/application-server
cp .env.example .env   # fill in real values
./setup.sh              # creates the shared `shared` docker network, deploys app.yml + mon.yml

# Deploy a standalone stack (repeat per stack you need)
cd ../n8n
cp .env.example .env
docker compose up -d
```

---

## Recovery / Disaster Recovery

See [`../../docker/RESTORE.md`](../../docker/RESTORE.md) — covers recovering
this node's data from a pulled SD card, including which volumes/bind-mounts
belong to which stack above.

---

## Monitoring

**Metrics**: http://localhost:9100/metrics
**Prometheus Scrape**: `anno-app-opi3bp-01:9100`

**Key Metrics to Monitor**:
- CPU usage (should be <80%)
- Memory usage (available should be >100MB)
- Disk usage (should be <85%)
- Container count and status

---

## Troubleshooting

```bash
# Check logs for a given stack
cd docker/<stack> && docker compose logs -f

# Check resources
docker stats

# Restart a stack
cd docker/<stack> && docker compose restart

# Out of disk space
df -h
docker system prune -a
```

---

## Useful Commands

```bash
# View all containers on this node
docker ps

# Per-stack: view services, logs, restart
cd docker/<stack>
docker compose ps
docker compose logs -f
docker compose restart <service>
docker compose pull && docker compose up -d
```

---

## Network Access

**Local Network**: `http://anno-app-opi3bp-01.local`
**Tailscale**: `http://100.x.x.x` (replace with actual IP)
**External**: via Cloudflare Tunnel (see gateway node)

---

**For the full picture**: [`../../docs/architecture/nodes-inventory.md`](../../docs/architecture/nodes-inventory.md)
**Service catalog**: [`../../docker/README.md`](../../docker/README.md)

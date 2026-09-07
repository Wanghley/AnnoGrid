# docker/ — Service Catalog

Every deployable Docker Compose stack in AnnoGrid, one directory per service.
This is the **catalog of what can be deployed**; `../nodes/` documents
**which of these actually run on which physical/cloud machine** — see each
node's README for its deployment inventory (e.g.
[`../nodes/anno-app-opi3bp-01/README.md`](../nodes/anno-app-opi3bp-01/README.md)).

Each directory is self-contained: `docker-compose.yml` (or a set of
`docker-compose.*.yml` files) + `.env.example`. Copy `.env.example` to `.env`
and fill in real values before running `docker compose up -d` — `.env` files
are gitignored on purpose (see root `.gitignore`).

---

## Layout

```
docker/
├── application-server/   # Core AnnoGrid stack: app.yml + mon.yml + setup.sh/manage.sh
│                          # (db.yml is a retired no-op — DBs moved to anno-db-oci-01)
├── core-data/             # DEPRECATED no-op stub — was postgres/mariadb/redis/minio,
│                          # now on ../nodes/anno-db-oci-01/
├── n8n/                   # Workflow automation
├── tandoor/               # Recipe manager
├── twenty-personal-crm/   # CRM
├── obsidian/               # CouchDB sync backend for Obsidian LiveSync
├── homarr/                 # Dashboard
├── portainer/               # Docker management UI
├── peekaping/               # Uptime monitoring
├── homepage/                 # Dashboard (homepage.sh cron + stats.json)
├── restore/                   # SD-card recovery tooling — see ../RESTORE.md
├── ai-jetson-orin/             # AI/ML node stacks (hermes-agent, litellm, monitoring)
├── gateway-monitoring-server/   # Gateway/monitoring node stack (grafana)
└── shared/                       # Cross-cutting / not tied to one specific node
    ├── canary/                     # Canary deployment monitoring (runs on NAS)
    ├── general/                     # setup-node.sh + watchtower (auto-updates)
    ├── monitoring/                   # Standalone monitoring stack
    └── wppconnect/                    # WhatsApp connector
```

## Why the flat layout

`core-data/`, `n8n/`, `tandoor/`, `twenty-personal-crm/`, `obsidian/`,
`homarr/`, `portainer/`, `peekaping/`, and `homepage/` used to live nested
under `application-server/`, which made it look like they were sub-components
of the core stack rather than independently-deployed services that happen to
run on the same node. They're now flat siblings under `docker/` — each is
its own thing, deployed and versioned independently, regardless of which
node(s) end up running it.

`application-server/` keeps only what's genuinely "the core stack": the
base `docker-compose.app.yml` / `docker-compose.mon.yml` files, `setup.sh` /
`manage.sh`, and shared `configs/`. `docker-compose.db.yml` stays here too,
as a retired no-op — see [`../docs/guides/db-migration-to-oci.md`](../docs/guides/db-migration-to-oci.md).

`docker/canary`, `docker/general`, `docker/monitoring`, `docker/wppconnect`
don't map cleanly to one node, so they're grouped under `shared/` instead of
sitting at the top level.

`docker/ai-jetson-orin/` and `docker/gateway-monitoring-server/` still nest
their sub-stacks the old way — not touched in this pass.

---

## Related

- [`RESTORE.md`](RESTORE.md) — recovering data from a pulled SD card
- [`../docs/guides/db-migration-to-oci.md`](../docs/guides/db-migration-to-oci.md) — DB migration to `anno-db-oci-01`
- [`../docs/architecture/nodes-inventory.md`](../docs/architecture/nodes-inventory.md) — hardware/network per node

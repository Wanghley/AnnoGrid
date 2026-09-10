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
├── core-data/             # postgres/mariadb/redis/couchdb/minio — deployed on anno-db-oci-01
├── n8n/                   # Workflow automation
├── tandoor/               # Recipe manager
├── twenty-personal-crm/   # CRM
├── obsidian/               # DEPRECATED no-op — couchdb moved into core-data/
├── homarr/                 # Dashboard
├── portainer/               # Docker management UI
├── peekaping/               # Uptime monitoring
├── homepage/                 # Dashboard (homepage.sh cron + stats.json)
├── restore/                   # SD-card recovery tooling — see ../RESTORE.md
├── ai-jetson-orin/             # AI/ML node stacks (hermes-agent, litellm, monitoring)
└── shared/                       # Cross-cutting / not tied to one specific node
    ├── canary/                     # Canary deployment monitoring (runs on NAS)
    ├── general/                     # watchtower (auto-updates)
    ├── monitoring/                   # Edge-node sidecar: node-exporter + cAdvisor +
    │                                 # promtail, pointed at the monitoring Pi's Loki/
    │                                 # Prometheus. Deploy this on any node not already
    │                                 # covered by nodes/*/docker-compose.yml.
    └── wppconnect/                    # WhatsApp connector
```

There is no `gateway-monitoring-server/` here anymore — that stack (plus a
second, independent draft of it in `scripts/setup-gateway-monitoring.sh`,
and a third sidecar generator in `docker/shared/general/setup-node.sh`)
were three separate, mutually-contradictory scaffolds for the same
gateway/monitoring node, none of which actually worked end-to-end (Loki was
never wired up in any of them). They've been deleted. The real, working
stack is split across
[`nodes/anno-gw-mon-rpi3bp-01/`](../nodes/anno-gw-mon-rpi3bp-01/README.md)
(Prometheus/Loki/Alertmanager) and
[`nodes/anno-gw-vps-macauba-01/`](../nodes/anno-gw-vps-macauba-01/README.md)
(Grafana + public ingress) — see those READMEs.

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
as a retired no-op — its services moved into `core-data/`, which now runs on
`anno-db-oci-01` instead of `anno-app-opi3bp-01` — see
[`../docs/guides/db-migration-to-oci.md`](../docs/guides/db-migration-to-oci.md).
`obsidian/` is retired the same way (2026-09-08) — its couchdb also moved
into `core-data/`.

`docker/canary`, `docker/general`, `docker/monitoring`, `docker/wppconnect`
don't map cleanly to one node, so they're grouped under `shared/` instead of
sitting at the top level.

`docker/ai-jetson-orin/` still nests its sub-stacks the old way — not
touched in this pass.

---

## Related

- [`RESTORE.md`](RESTORE.md) — recovering data from a pulled SD card
- [`../docs/guides/db-migration-to-oci.md`](../docs/guides/db-migration-to-oci.md) — DB migration to `anno-db-oci-01`
- [`../docs/architecture/nodes-inventory.md`](../docs/architecture/nodes-inventory.md) — hardware/network per node

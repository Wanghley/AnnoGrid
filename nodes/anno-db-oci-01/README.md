# anno-db-oci-01: Database Server Node

**Hardware**: Oracle Cloud Infrastructure VPS
**Role**: Runs `docker/core-data/` — centralized PostgreSQL, MariaDB, Redis, MinIO for all AnnoGrid app stacks
**Status**: 🟡 Provisioning — see [`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)

---

## What's deployed here

| Stack | What it is |
|---|---|
| [`docker/core-data/`](../../docker/core-data/README.md) | PostgreSQL, MariaDB, Redis, MinIO, node-exporter |

This node runs exactly one stack. For setup, backups, monitoring, and
troubleshooting, see [`docker/core-data/README.md`](../../docker/core-data/README.md)
— this file only covers node-level access.

Postgres/MariaDB/Redis/MinIO used to run as local containers on
`anno-app-opi3bp-01` (two separate stacks — see
[`docs/guides/db-migration-to-oci.md`](../../docs/guides/db-migration-to-oci.md)
for the full history). Every AnnoGrid app service reaches this node **only
over Tailscale** — no database port is ever exposed to the public internet.

---

## Access

```bash
ssh ubuntu@anno-db-oci-01.<your-tailnet>.ts.net
```

There is no local-network path to this node — Tailscale is the only route.

---

**For the full picture**: [`../../docs/architecture/nodes-inventory.md`](../../docs/architecture/nodes-inventory.md)
**Service catalog**: [`../../docker/README.md`](../../docker/README.md)

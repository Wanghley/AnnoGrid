# anno-gw-mon-rpi3bp-01: Monitoring Node

**Hardware**: Raspberry Pi 3B+ (1GB RAM)
**Role**: Metrics + logs + alerting for the whole cluster — nothing else
**Services**: Prometheus, Loki, Alertmanager, node-exporter, cAdvisor, docker socket-proxy
**Reachable from**: Tailscale only — this node has no public ingress and no cloudflared

---

## Architecture note (2026-09-09)

This node used to run Grafana and `cloudflared` itself. Both moved off:

- **Public ingress** → [`nodes/anno-gw-vps-macauba-01/`](../anno-gw-vps-macauba-01/README.md),
  a VPS that terminates the Cloudflare Tunnel.
- **Grafana** → also moved to that VPS (more headroom there, and it sits
  right next to the tunnel that serves it publicly instead of needing a
  Tailscale hop for every request). Grafana reaches this Pi's Prometheus
  and Loki as remote datasources over Tailscale.

What's left here is the pure data plane: scrape, store, alert. This box is
never reachable from the public internet, even through a tunnel — only from
inside the tailnet.

If you're wondering why this directory looks different from a stale copy
you might have seen elsewhere in the repo: see "What was wrong" at the
bottom.

## Stack

| Service | Purpose | Port (Tailscale-only) |
|---|---|---|
| Prometheus | metrics store + scraper | 9090 |
| Loki | log storage | 3100 (edge nodes push here) |
| Alertmanager | alert routing | 9093 |
| node-exporter | this host's own metrics | internal only |
| cAdvisor | this host's container metrics | internal only |
| docker socket-proxy | read-only container list, for Homepage on another node | 2375 |

Every service has a hard memory ceiling in `docker-compose.yml`:

| Service | Limit |
|---|---|
| prometheus | 256M |
| loki | 160M |
| cadvisor | 96M |
| promtail | 64M |
| node-exporter | 48M |
| alertmanager | 48M |
| docker-proxy | 32M |
| **Total ceiling** | **~700M** |

That's a safety ceiling per container, not a reservation — steady-state
usage with 4-5 scrape targets at a 30s interval sits well under it. It's
sized to leave headroom for the OS + Docker daemon on a device with ~700MB
usable after boot. Enable zram as a swap backstop:

```bash
sudo ENABLE_ZRAM=1 scripts/gateway-monitoring/gateway-node-setup.sh
```

## Quick Start

```bash
# 1. OS prep (once, on a fresh Pi) — installs ufw/fail2ban/nftables/zram etc.
#    Does NOT touch Docker or this stack.
sudo ENABLE_ZRAM=1 scripts/gateway-monitoring/gateway-node-setup.sh

# 2. Configure this stack
cd nodes/anno-gw-mon-rpi3bp-01
cp .env.example .env
vim .env                                          # set TAILSCALE_IP
vim prometheus-config/targets/cluster-nodes.yml   # set real peer Tailscale IPs

# 3. Deploy (validates .env, then docker compose up -d)
./setup.sh
```

Access (from inside the tailnet only):
- Prometheus: `http://<TAILSCALE_IP>:9090`
- Alertmanager: `http://<TAILSCALE_IP>:9093`
- Loki push endpoint: `http://<TAILSCALE_IP>:3100/loki/api/v1/push`

Grafana lives on `anno-gw-vps-macauba-01` and is configured to reach this
Pi's Prometheus/Loki automatically — see that node's README.

## Adding/editing scrape targets

Peer node IPs live in **one file**:
[`prometheus-config/targets/cluster-nodes.yml`](prometheus-config/targets/cluster-nodes.yml).
Prometheus watches it and hot-reloads on save — no restart needed. Don't add
peer targets anywhere else; that duplication is exactly what caused this
stack to have three different guessed IPs for the same node before.

## Shipping logs/metrics from other nodes

Every other node (app/AI/NAS/gateway-VPS) runs the sidecar in
[`docker/shared/monitoring/`](../../docker/shared/monitoring/README.md)
(node-exporter + cAdvisor + promtail), pointed at this Pi's `TAILSCALE_IP`:
- Metrics: this Pi's Prometheus scrapes them via `cluster-nodes.yml` (pull).
- Logs: their promtail pushes to `http://<TAILSCALE_IP>:3100/loki/api/v1/push`.

## Alerting

Rules live in `prometheus-config/rules/*.yml` (node down, high CPU/mem,
low disk, high temp). Alertmanager's default receiver is a no-op —
`alertmanager-config/alertmanager.yml` has commented-out Slack/webhook
examples. Wire one up before relying on this for anything. Grafana on the
VPS can also add this Pi's Alertmanager (`http://<TAILSCALE_IP>:9093`) as a
datasource to view/silence alerts from the Grafana UI.

## Recommended Grafana dashboards (import by ID, from the VPS's Grafana)

- `1860` — Node Exporter Full
- `13639` — Loki Logs
- cAdvisor / Docker container dashboards — search "cadvisor" in the Grafana gallery

## What was wrong before this rewrite

This directory's `docker-compose.yml` used to mount `./alertmanager-config/`
and `./grafana-provisioning/` — directories that didn't exist on disk, so
Alertmanager crash-looped and Grafana came up with no datasource. Loki was
commented out entirely. `prometheus.yml` used `${VAR}`-style templating that
plain `prom/prometheus` never expands, and `remote_write`d metrics to a
`CENTRAL_PROM_URL` that doesn't exist — backwards, since this node is the
hub, not a forwarder. `setup.sh` was an accidental copy of the unrelated
OS-package installer and never touched Docker.

Three *other* drafts of this same stack existed elsewhere in the repo, each
guessing different Tailscale IPs for the same three peer nodes:
`docker/gateway-monitoring-server/` and `scripts/setup-gateway-monitoring.sh`
have been deleted (their one real secret, the Cloudflare tunnel token,
moved to `nodes/anno-gw-vps-macauba-01/.env`, since that's where cloudflared
runs now). `docker/shared/general/setup-node.sh` — a second, inferior
implementation of the edge-node sidecar — was also deleted in favor of
[`docker/shared/monitoring/`](../../docker/shared/monitoring/), which is
git-tracked and follows the same "edit a compose file + `.env`, `docker
compose up -d`" pattern every other node in this repo uses. This directory
is now the only place the monitoring hub is defined.

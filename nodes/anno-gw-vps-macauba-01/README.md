# anno-gw-vps-macauba-01: Gateway Node (VPS)

**Hardware**: VPS (cloud, not an SBC — this is the one box in the cluster with a public IP)
**Role**: Public ingress (Cloudflare Tunnel) + Grafana
**Services**: cloudflared, Grafana, node-exporter, promtail
**Reachable from**: The public internet (only through the Cloudflare Tunnel — no ports are opened directly), and Tailscale

---

## Architecture note (2026-09-09)

This node exists to take two things off the 1GB monitoring Pi
([`nodes/anno-gw-mon-rpi3bp-01/`](../anno-gw-mon-rpi3bp-01/README.md)):

1. **Public ingress.** `cloudflared` used to run on the Pi. It's here now,
   so a Pi reboot/OOM doesn't take down the tunnel, and the Pi itself never
   needs to be internet-facing even indirectly.
2. **Grafana.** Moved here because this box has real headroom, and because
   putting it next to the tunnel means the public path is
   `internet → cloudflared → grafana` (same host, same docker network) —
   no Tailscale hop for every dashboard render, unlike the old setup where
   cloudflared on the Pi had to reach Grafana locally and everything else
   had to cross Tailscale anyway.

Grafana's data still lives on the Pi: its Prometheus and Loki are wired up
here as remote datasources over Tailscale (see
`grafana-provisioning/datasources/datasources.yml`). Alertmanager also
stays on the Pi — only its UI is exposed publicly, via a Cloudflare Public
Hostname rule pointed at the Pi's Tailscale IP.

## Stack

| Service | Purpose |
|---|---|
| cloudflared | terminates the Cloudflare Tunnel, proxies to Grafana + (via Tailscale) the Pi's Alertmanager |
| Grafana | dashboards — queries the Pi's Prometheus/Loki remotely |
| node-exporter | this box's own metrics, scraped by the Pi's Prometheus |
| promtail | ships this box's own logs to the Pi's Loki |

## Prerequisites

- Docker + Docker Compose v2 on the VPS.
- A Cloudflare Tunnel already created (Zero Trust dashboard → Networks →
  Tunnels) with a token.
- This VPS able to join the AnnoGrid tailnet (approve it in the Tailscale
  admin console after `tailscale up`).

## Quick Start

```bash
cd nodes/anno-gw-vps-macauba-01

# 1. Join the tailnet (one-time, needs sudo)
sudo ./setup.sh --join-tailnet
# ... follow the printed auth link, then note the Tailscale IP it prints.

# 2. Configure
cp .env.example .env
vim .env   # TAILSCALE_IP (from step 1), CF_TUNNEL_TOKEN, GRAFANA_ADMIN_PASSWORD

# 3. Deploy (validates .env, then docker compose up -d)
./setup.sh
```

Then in the Cloudflare Zero Trust dashboard, add Public Hostname rules on
this tunnel:

| Public hostname | Service |
|---|---|
| `grafana.yourdomain.com` | `http://grafana:3000` |
| `alertmanager.yourdomain.com` | `http://<anno-gw-mon-rpi3bp-01's TAILSCALE_IP>:9093` |

The first rule stays entirely inside this box's docker network. The second
crosses Tailscale to the monitoring Pi.

## Grafana's backend database

Defaults to local sqlite (`grafana-data` volume) — simplest option, fine
for one Grafana instance. `.env` also has `GF_DATABASE_*` vars to point it
at the central Postgres on `anno-db-oci-01` instead (a `grafana_central`
DB/user was already provisioned there for this). If you use it, **verify
the host IP in `.env` first** — it was carried forward from an old config
file full of stale guessed IPs, and is the one value in this setup I
couldn't independently re-verify against a second source. If it's wrong,
Grafana will fail to start; blank out `GF_DATABASE_TYPE` to fall back to
sqlite.

## Adding Grafana dashboards

Import by ID in the Grafana UI (`https://grafana.yourdomain.com` once the
tunnel rule is live): `1860` (Node Exporter Full), `13639` (Loki Logs), or
search "cadvisor" for container dashboards.

## Recovery

This box has no durable data of its own that matters except `grafana-data`
(dashboards you built by hand, not provisioned ones — those are in git) and
whatever's in the central Postgres if you switched to that backend. Losing
this VPS means: re-run Quick Start on a new box, restore `grafana-data` (or
just re-point at the same central Postgres and lose nothing), get a new
`CF_TUNNEL_TOKEN` if the old tunnel was deleted, re-add the Public Hostname
rules.

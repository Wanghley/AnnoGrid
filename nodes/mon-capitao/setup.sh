#!/usr/bin/env bash
#
# setup.sh — deploy the monitoring stack on anno-gw-mon-rpi3bp-01.
#
# This does NOT touch the OS (packages, ufw, zram, etc) — that's
# scripts/gateway-monitoring/gateway-node-setup.sh, run separately on a
# fresh Pi. This script only validates config and brings up the Docker
# Compose stack defined in this directory.
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Run gateway-node-setup.sh first, then install Docker." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' (v2 plugin) not found." >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "No .env found — copying .env.example. Edit it before re-running." >&2
  cp .env.example .env
  exit 1
fi

# Catch the most common way to shoot yourself in the foot: deploying with
# placeholder values still in .env.
missing=0
for var in TAILSCALE_IP GATEWAY_ID; do
  val="$(grep -E "^${var}=" .env | head -n1 | cut -d= -f2-)"
  if [ -z "$val" ] || [ "$val" = "changeme" ] || [[ "$val" == *"x.x.x"* ]]; then
    echo "ERROR: $var in .env still looks like a placeholder ('$val')." >&2
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  exit 1
fi

if grep -q "100.x.x.x" prometheus-config/targets/cluster-nodes.yml; then
  echo "WARNING: prometheus-config/targets/cluster-nodes.yml still has 100.x.x.x placeholders." >&2
  echo "         The cluster-nodes scrape job will fail until you fill in real Tailscale IPs." >&2
fi

echo "Pulling images..."
docker compose pull

echo "Starting stack..."
docker compose up -d

echo ""
echo "------------------------------------------------------------"
echo "Deployed. From inside the tailnet:"
TS_IP="$(grep -E '^TAILSCALE_IP=' .env | cut -d= -f2-)"
echo "  Prometheus:   http://${TS_IP}:9090"
echo "  Alertmanager: http://${TS_IP}:9093"
echo "  Loki push:    http://${TS_IP}:3100/loki/api/v1/push"
echo ""
echo "  Grafana lives on anno-gw-vps-macauba-01, not here."
echo ""
echo "Check status: docker compose ps"
echo "------------------------------------------------------------"

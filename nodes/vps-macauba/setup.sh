#!/usr/bin/env bash
#
# setup.sh — bootstrap Tailscale (if needed) and deploy the stack on
# anno-gw-vps-macauba-01.
#
# Usage:
#   sudo ./setup.sh --join-tailnet   # first run on a fresh VPS
#   ./setup.sh                       # validate .env and deploy
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--join-tailnet" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: --join-tailnet must be run as root (sudo)." >&2
    exit 1
  fi
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  echo "Bringing up Tailscale — follow the printed auth link."
  tailscale up
  echo ""
  echo "This VPS's Tailscale IP: $(tailscale ip -4)"
  echo "Put that in .env as TAILSCALE_IP, then rerun ./setup.sh (no args)."
  exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "ERROR: Tailscale isn't installed. Run: sudo ./setup.sh --join-tailnet" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed." >&2
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
for var in TAILSCALE_IP CF_TUNNEL_TOKEN GATEWAY_IP GRAFANA_ADMIN_PASSWORD; do
  val="$(grep -E "^${var}=" .env 2>/dev/null | head -n1 | cut -d= -f2-)"
  if [ -z "$val" ] || [ "$val" = "changeme" ] || [[ "$val" == *"x.x.x"* ]]; then
    echo "ERROR: $var in .env still looks like a placeholder ('$val')." >&2
    missing=1
  fi
done
if [ "$missing" -eq 1 ]; then
  exit 1
fi

echo "Pulling images..."
docker compose pull

echo "Starting stack..."
docker compose up -d

echo ""
echo "------------------------------------------------------------"
echo "Deployed. From inside the tailnet:"
TS_IP="$(grep -E '^TAILSCALE_IP=' .env | cut -d= -f2-)"
echo "  Grafana:       http://${TS_IP}:3000"
echo "  node-exporter: http://${TS_IP}:9100/metrics"
echo ""
echo "Public access: whatever Public Hostname rules you've set in the"
echo "Cloudflare Zero Trust dashboard for this tunnel."
echo ""
echo "Check status: docker compose ps"
echo "------------------------------------------------------------"

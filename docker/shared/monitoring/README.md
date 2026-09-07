AnnoGrid: Centralized Monitoring Stack

This directory contains the configuration for the AnnoGrid Observability Pipeline. It allows for centered monitoring of a multi-node edge cluster using a Gateway-Agent architecture.

🏗 System Architecture

The monitoring follows a "Hub and Spoke" model:

The Hub (Gateway): A Raspberry Pi 3B+ running the core database (Prometheus) and visualization (Grafana).

The Spokes (Edge Nodes): Orange Pi 3B, NVIDIA Jetson Nano, and Raspberry Pi 3B+ (NAS) running lightweight exporters.

The Backhaul: All data is transmitted over Tailscale Mesh VPN to ensure end-to-end encryption without opening firewall ports.

🛠 Setup: The Edge Node "Sidecar"

Each node in the cluster runs a "Sidecar" stack to ship metrics and logs back to the Gateway.

1. Requirements

Docker & Docker Compose (Non-root access recommended).

Tailscale installed and authenticated.

Environment File (.env):

Bash


GATEWAY_IP=100.x.y.z  # The Tailscale IP of your Gateway node

NODE_NAME=anno-node-01 # Unique hostname for this cluster node

2. Services Deployed

Node Exporter: Exposes hardware-level metrics (CPU, RAM, Disk, Network).

Netdata: Provides per-second, high-resolution telemetry for local troubleshooting.

Promtail: Tails Docker container and system logs, shipping them to the central Loki instance.

📈 Centralized Configuration

Metrics (Prometheus)

The Gateway is configured to scrape each node via its Tailscale IP to maintain the Zero Trust posture.

YAML


scrape_configs:

  - job_name: 'nodes'

    static_configs:

      - targets: ['100.x.x.x:9100', '100.y.y.y:9100'] # Edge Node Tailscale IPs

Logging (Loki)

Edge nodes use Environment Variable Expansion to dynamically point to the Gateway's log aggregator:

YAML


clients:

  - url: http://${GATEWAY_IP}:3100/loki/api/v1/push

🔐 Security (Zero Trust Architecture)

Identity-Based Access: The Grafana dashboard is protected by Cloudflare Access. Users must authenticate via email OTP before accessing the grid data.

Encrypted Scrapes: No monitoring data travels over the public internet or the local unencrypted subnet.

No Port Forwarding: The Gateway uses a Cloudflare Tunnel (cloudflared) to bypass NAT and remain "dark" to external scans.

🚀 Performance Optimizations

ZRAM: Enabled on the RPi 3B+ Gateway to handle the memory overhead of the monitoring database (Loki/Prometheus).

Scrape Intervals: Set to 30s to minimize CPU impact on low-power SBCs while maintaining useful resolution.

SD Card Protection: TSDB retention is limited to 7 days to minimize write cycles and prolong storage life.

📋 Recommended Dashboards

Import these IDs into Grafana for an instant AnnoGrid view:

ID 1860: Node Exporter Full (Complete cluster health).

ID 14990: Netdata (Per-node real-time metrics).

ID 13639: Loki Logs (Searchable logs from every container in the grid).

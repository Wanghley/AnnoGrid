#!/bin/bash
#
# setup-gateway-monitoring.sh
# Complete setup script for anno-gw-mon-rpi3bp-01
# Handles: Prometheus, Grafana, Uptime Kuma, Node Exporter, Cloudflared, Tailscale
#

set -euo pipefail

# ─── CONFIGURATION ─────────────────────────────────────────────────────────────
NODE_NAME="anno-gw-mon-rpi3bp-01"
BASE_DIR="/home/$(whoami)/annogrid"
DOCKER_NETWORK="monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── PRE-FLIGHT CHECKS ─────────────────────────────────────────────────────────

check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    log_info "All requirements met."
}

# ─── DIRECTORY STRUCTURE ───────────────────────────────────────────────────────

setup_directories() {
    log_info "Setting up directory structure..."
    
    mkdir -p "$BASE_DIR"/{prometheus,grafana,uptime-kuma,node-exporter,cloudflared,configs}
    mkdir -p "$BASE_DIR/node-exporter/textfile_collector"
    
    # Set permissions for Grafana (runs as user 472)
    sudo chown -R 472:472 "$BASE_DIR/grafana" 2>/dev/null || true
    
    log_info "Directories created at $BASE_DIR"
}

# ─── CREATE DOCKER NETWORK ─────────────────────────────────────────────────────

setup_network() {
    log_info "Setting up Docker network..."
    
    if ! docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
        docker network create "$DOCKER_NETWORK"
        log_info "Created network: $DOCKER_NETWORK"
    else
        log_info "Network $DOCKER_NETWORK already exists"
    fi
}

# ─── PROMETHEUS CONFIGURATION ──────────────────────────────────────────────────

create_prometheus_config() {
    log_info "Creating Prometheus configuration..."
    
    cat > "$BASE_DIR/configs/prometheus.yml" << 'EOF'
# Prometheus configuration for AnnoGrid Gateway/Monitoring Node
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'annogrid'
    node: 'anno-gw-mon-rpi3bp-01'

# Alerting configuration (optional - uncomment if using Alertmanager)
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets:
#           - alertmanager:9093

# Rule files (optional)
# rule_files:
#   - /etc/prometheus/rules/*.yml

scrape_configs:
  # Self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'anno-gw-mon-rpi3bp-01'

  # Local Node Exporter
  - job_name: 'node-exporter-local'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'anno-gw-mon-rpi3bp-01'
          role: 'gateway-monitoring'

  # AnnoGrid Nodes via Tailscale
  - job_name: 'anno-nodes'
    static_configs:
      # Application Server
      - targets: ['100.123.0.5:9100']
        labels:
          instance: 'anno-app-opi3b-01'
          role: 'application'
      # NAS Server
      - targets: ['100.101.173.125:9100']
        labels:
          instance: 'anno-nas-opi3bp-01'
          role: 'storage'
      # Gateway/Monitoring (via Tailscale for consistency)
      - targets: ['100.75.28.18:9100']
        labels:
          instance: 'anno-gw-mon-rpi3bp-01'
          role: 'gateway-monitoring'

  # cAdvisor for container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
        labels:
          instance: 'anno-gw-mon-rpi3bp-01'

  # Uptime Kuma metrics (if enabled)
  - job_name: 'uptime-kuma'
    static_configs:
      - targets: ['uptime-kuma:3001']
        labels:
          instance: 'anno-gw-mon-rpi3bp-01'
    metrics_path: /metrics
EOF

    log_info "Prometheus configuration created"
}

# ─── GRAFANA PROVISIONING ──────────────────────────────────────────────────────

create_grafana_provisioning() {
    log_info "Creating Grafana provisioning configs..."
    
    mkdir -p "$BASE_DIR/configs/grafana/provisioning/"{datasources,dashboards}
    
    # Datasource configuration
    cat > "$BASE_DIR/configs/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

    # Dashboard provider configuration
    cat > "$BASE_DIR/configs/grafana/provisioning/dashboards/default.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'AnnoGrid Dashboards'
    orgId: 1
    folder: 'AnnoGrid'
    folderUid: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log_info "Grafana provisioning created"
}

# ─── DOCKER COMPOSE FILE ───────────────────────────────────────────────────────

create_docker_compose() {
    log_info "Creating Docker Compose file..."
    
    cat > "$BASE_DIR/docker-compose.yml" << EOF
# AnnoGrid Gateway & Monitoring Stack
# Node: anno-gw-mon-rpi3bp-01

services:
  # ─── PROMETHEUS ──────────────────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    hostname: prometheus
    restart: always
    ports:
      - "9090:9090"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=15d"
      - "--storage.tsdb.retention.size=5GB"
      - "--web.console.libraries=/usr/share/prometheus/console_libraries"
      - "--web.console.templates=/usr/share/prometheus/consoles"
      - "--web.enable-lifecycle"
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=monitoring"
      - "com.annogrid.component=prometheus"
      - "com.annogrid.node=${NODE_NAME}"

  # ─── GRAFANA ─────────────────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    hostname: grafana
    restart: always
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_ADMIN_PASSWORD:-annogrid}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=\${GRAFANA_ROOT_URL:-http://localhost:3000}
      - GF_PANELS_DISABLE_SANITIZE_HTML=true
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel
    volumes:
      - grafana-data:/var/lib/grafana
      - ./configs/grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - prometheus
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=monitoring"
      - "com.annogrid.component=grafana"
      - "com.annogrid.node=${NODE_NAME}"

  # ─── UPTIME KUMA ─────────────────────────────────────────────────────────────
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    hostname: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma-data:/app/data
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=monitoring"
      - "com.annogrid.component=uptime-kuma"
      - "com.annogrid.node=${NODE_NAME}"

  # ─── NODE EXPORTER ───────────────────────────────────────────────────────────
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    hostname: node-exporter
    restart: always
    ports:
      - "9100:9100"
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--path.rootfs=/rootfs"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
      - "--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"
      - "--no-collector.ipvs"
      - "--no-collector.wifi"
      - "--collector.netclass.ignored-devices=^(lo|docker[0-9]+|br-.+|veth.+)$$"
      - "--collector.netdev.device-exclude=^(lo|docker[0-9]+|br-.+|veth.+)$$"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
      - ./node-exporter/textfile_collector:/var/lib/node_exporter/textfile_collector:ro
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=monitoring"
      - "com.annogrid.component=node-exporter"
      - "com.annogrid.node=${NODE_NAME}"

  # ─── CADVISOR ────────────────────────────────────────────────────────────────
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    hostname: cadvisor
    restart: always
    ports:
      - "8080:8080"
    privileged: true
    command:
      - "-logtostderr"
      - "-docker_only"
      - "-housekeeping_interval=30s"
      - "-disable_metrics=percpu,sched,tcp,udp,disk,diskIO,hugetlb,referenced_memory,cpu_topology,resctrl"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
    devices:
      - /dev/kmsg
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=monitoring"
      - "com.annogrid.component=cadvisor"
      - "com.annogrid.node=${NODE_NAME}"

  # ─── CLOUDFLARED (TUNNEL) ────────────────────────────────────────────────────
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    hostname: cloudflared
    restart: always
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=\${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "com.annogrid.service=networking"
      - "com.annogrid.component=cloudflared"
      - "com.annogrid.node=${NODE_NAME}"
    profiles:
      - cloudflare  # Only start when explicitly requested

# ─── VOLUMES ───────────────────────────────────────────────────────────────────
volumes:
  prometheus-data:
    name: annogrid-prometheus-data
  grafana-data:
    name: annogrid-grafana-data
  uptime-kuma-data:
    name: annogrid-uptime-kuma-data

# ─── NETWORKS ──────────────────────────────────────────────────────────────────
networks:
  ${DOCKER_NETWORK}:
    external: true
    name: ${DOCKER_NETWORK}
EOF

    log_info "Docker Compose file created"
}

# ─── ENVIRONMENT FILE ──────────────────────────────────────────────────────────

create_env_file() {
    log_info "Creating environment file..."
    
    if [[ ! -f "$BASE_DIR/.env" ]]; then
        cat > "$BASE_DIR/.env" << 'EOF'
# AnnoGrid Gateway/Monitoring Environment Variables
# Node: anno-gw-mon-rpi3bp-01

# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=annogrid_secure_password
GRAFANA_ROOT_URL=http://localhost:3000

# Cloudflare Tunnel (get token from Cloudflare Zero Trust dashboard)
# CLOUDFLARE_TUNNEL_TOKEN=your_tunnel_token_here

# Tailscale (if using containerized Tailscale)
# TAILSCALE_AUTH_KEY=tskey-auth-xxxxx
EOF
        log_warn "Created .env file - please update with your credentials!"
    else
        log_info ".env file already exists, skipping"
    fi
}

# ─── MANAGEMENT SCRIPT ─────────────────────────────────────────────────────────

create_management_script() {
    log_info "Creating management script..."
    
    cat > "$BASE_DIR/annogrid-monitor.sh" << 'EOF'
#!/bin/bash
#
# annogrid-monitor.sh
# Management script for AnnoGrid monitoring stack
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

case "$1" in
    start)
        echo "Starting AnnoGrid monitoring stack..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping AnnoGrid monitoring stack..."
        docker compose down
        ;;
    restart)
        echo "Restarting AnnoGrid monitoring stack..."
        docker compose restart
        ;;
    status)
        echo "AnnoGrid monitoring stack status:"
        docker compose ps
        ;;
    logs)
        shift
        docker compose logs -f "$@"
        ;;
    update)
        echo "Updating AnnoGrid monitoring stack..."
        docker compose pull
        docker compose up -d
        ;;
    cloudflare-start)
        echo "Starting Cloudflare tunnel..."
        docker compose --profile cloudflare up -d cloudflared
        ;;
    cloudflare-stop)
        echo "Stopping Cloudflare tunnel..."
        docker compose stop cloudflared
        ;;
    reload-prometheus)
        echo "Reloading Prometheus configuration..."
        curl -X POST http://localhost:9090/-/reload
        ;;
    backup)
        echo "Backing up monitoring data..."
        BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        docker run --rm -v annogrid-prometheus-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/prometheus.tar.gz -C /data .
        docker run --rm -v annogrid-grafana-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/grafana.tar.gz -C /data .
        docker run --rm -v annogrid-uptime-kuma-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/uptime-kuma.tar.gz -C /data .
        echo "Backup created at $BACKUP_DIR"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|update|cloudflare-start|cloudflare-stop|reload-prometheus|backup}"
        exit 1
        ;;
esac
EOF

    chmod +x "$BASE_DIR/annogrid-monitor.sh"
    log_info "Management script created"
}

# ─── SYSTEMD SERVICE ───────────────────────────────────────────────────────────

create_systemd_service() {
    log_info "Creating systemd service..."
    
    sudo tee /etc/systemd/system/annogrid-monitoring.service > /dev/null << EOF
[Unit]
Description=AnnoGrid Monitoring Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$BASE_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=$(whoami)
Group=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    log_info "Systemd service created (not enabled - run 'sudo systemctl enable annogrid-monitoring' to enable)"
}

# ─── MAIN ──────────────────────────────────────────────────────────────────────

main() {
    echo "========================================"
    echo "  AnnoGrid Gateway/Monitoring Setup"
    echo "  Node: $NODE_NAME"
    echo "========================================"
    echo ""
    
    check_requirements
    setup_directories
    setup_network
    create_prometheus_config
    create_grafana_provisioning
    create_docker_compose
    create_env_file
    create_management_script
    create_systemd_service
    
    echo ""
    echo "========================================"
    log_info "Setup complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $BASE_DIR/.env with your credentials"
    echo "  2. Update Prometheus targets in $BASE_DIR/configs/prometheus.yml"
    echo "  3. Start the stack:"
    echo "     cd $BASE_DIR && ./annogrid-monitor.sh start"
    echo ""
    echo "  Or enable auto-start on boot:"
    echo "     sudo systemctl enable annogrid-monitoring"
    echo ""
    echo "Access points:"
    echo "  - Prometheus: http://localhost:9090"
    echo "  - Grafana:    http://localhost:3000 (admin/annogrid_secure_password)"
    echo "  - Uptime Kuma: http://localhost:3001"
    echo "  - Node Exporter: http://localhost:9100/metrics"
    echo "  - cAdvisor:   http://localhost:8080"
    echo ""
}

main "$@"
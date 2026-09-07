#!/bin/bash

# Configuration Paths
DEPLOY_DIR="$HOME/node-mon-stack"
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
CONFIG_FILE="$DEPLOY_DIR/promtail-config.yml"
COCKPIT_OVERRIDE_DIR="/etc/systemd/system/cockpit.socket.d"
COCKPIT_LISTEN_CONF="$COCKPIT_OVERRIDE_DIR/listen.conf"

show_help() {
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --install    Setup configurations, Cockpit (custom port), and start containers."
    echo "  --remove     Stop containers and wipe all configurations/packages."
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install it first."
        exit 1
    fi
    # Check if daemon is responsive
    if ! sudo docker ps &> /dev/null; then
        echo "Error: Docker daemon is not running or sudo is required."
        exit 1
    fi
}

do_install() {
    check_docker
    
    # 1. Gather Inputs
    read -p "Enter Gateway (Loki) IP: " GATEWAY_IP
    read -p "Enter unique Node Name: " NODE_NAME
    read -p "Enter Cockpit Port [Default 80]: " COCKPIT_PORT
    COCKPIT_PORT=${COCKPIT_PORT:-80}

    mkdir -p "$DEPLOY_DIR"

    # 2. Install Cockpit & Certificate Tools
    echo "Installing Cockpit and sscg..."
    # Ensure a certificate exists so the webserver actually starts
    if [ ! -f /etc/cockpit/ws-certs.d/*.cert ]; then
       sudo remotectl certificate --ensure --user=root
    fi
    sudo apt-get update
    sudo apt-get install -y cockpit sscg
    
    # 3. Apply Port Override
    echo "Configuring Cockpit on port $COCKPIT_PORT..."
    sudo mkdir -p "$COCKPIT_OVERRIDE_DIR"
    sudo bash -c "cat <<EOF > $COCKPIT_LISTEN_CONF
[Socket]
ListenStream=
ListenStream=$COCKPIT_PORT
EOF"
	
    sudo remotectl certificate --ensure --user=root
    sudo systemctl daemon-reload
    sudo systemctl stop cockpit.socket cockpit.service 2>/dev/null
    sudo systemctl enable --now cockpit.socket

    # 4. Create Promtail Config
    cat <<EOF > "$CONFIG_FILE"
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://${GATEWAY_IP}:3100/loki/api/v1/push
scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        __path__: /var/log/*log
EOF

    # 5. Create Docker Compose
    cat <<EOF > "$COMPOSE_FILE"
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: always
    network_mode: "host"
    pid: "host"
    volumes:
      - /:/host:ro,rslave
    command:
      - '--path.rootfs=/host'

  netdata:
    image: netdata/netdata:latest
    container_name: netdata
    restart: always
    network_mode: "host"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - netdatalib:/var/lib/netdata
      - netdatacache:/var/cache/netdata
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: always
    environment:
      - GATEWAY_IP=${GATEWAY_IP}
      - NODE_NAME=${NODE_NAME}
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: 
      - -config.file=/etc/promtail/config.yml
      - -config.expand-env=true
      - -client.external-labels=host=${NODE_NAME}

volumes:
  netdatalib:
  netdatacache:
EOF
   
    if command -v ufw >/dev/null; then
    sudo ufw allow "$COCKPIT_PORT"/tcp
elif command -v firewall-cmd >/dev/null; then
    sudo firewall-cmd --permanent --add-port="$COCKPIT_PORT"/tcp
    sudo firewall-cmd --reload
fi
    # 6. Deploy
    echo "Deploying Docker stack..."
    sudo GATEWAY_IP=${GATEWAY_IP} NODE_NAME=${NODE_NAME} docker compose -f "$COMPOSE_FILE" up -d

    echo "------------------------------------------------"
    echo "Success!"
    echo "Cockpit: http://$(hostname -I | awk '{print $1}'):$COCKPIT_PORT"
    echo "Netdata: http://$(hostname -I | awk '{print $1}'):19999"
    echo "------------------------------------------------"
}

do_remove() {
    echo "--- Wiping Architecture ---"
    
    if [ -f "$COMPOSE_FILE" ]; then
        sudo docker compose -f "$COMPOSE_FILE" down -v
    fi

    echo "Removing Cockpit and Port Overrides..."
    sudo systemctl stop cockpit.socket 2>/dev/null
    sudo rm -rf "$COCKPIT_OVERRIDE_DIR"
    sudo apt-get purge -y cockpit sscg
    sudo apt-get autoremove -y
    sudo systemctl daemon-reload

    echo "Deleting configuration files..."
    rm -rf "$DEPLOY_DIR"
    
    echo "Removal complete."
}

# CLI Logic
case "$1" in
    --install) do_install ;;
    --remove)  do_remove  ;;
    *)         show_help  ;;
esac

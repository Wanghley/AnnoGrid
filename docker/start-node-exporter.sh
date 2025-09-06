#!/bin/bash
# start-node-exporter.sh
# Node Exporter deployment with explicit port mapping

NODE_NAME=${1:-$(hostname)}

echo "Starting node-exporter for node: $NODE_NAME"

# Ensure textfile collector directory exists
mkdir -p /var/lib/node_exporter/textfile_collector

# Remove existing container if present
docker rm -f node-exporter-$NODE_NAME 2>/dev/null || true

# Run Node Exporter container
docker run -d \
  --name=node-exporter-$NODE_NAME \
  --restart=always \
  -p 9100:9100 \
  -v "/:/host:ro,rslave" \
  -v "/etc/localtime:/etc/localtime:ro" \
  -v "/var/lib/node_exporter/textfile_collector:/host/var/lib/node_exporter/textfile_collector" \
  -l "com.annogrid.service=monitoring" \
  -l "com.annogrid.component=node-exporter" \
  -l "com.annogrid.node=$NODE_NAME" \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  prom/node-exporter \
  --path.rootfs=/host \
  --collector.textfile.directory=/host/var/lib/node_exporter/textfile_collector \
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/containerd/.+)($|/)" \
  --web.listen-address=:9100 \
  --web.telemetry-path=/metrics \
  --no-collector.wifi \
  --collector.netclass.ignored-devices="^(lo|docker[0-9]+|br-.+|veth.+)$" \
  --collector.netdev.device-exclude="^(lo|docker[0-9]+|br-.+|veth.+)$" \
  --no-collector.hwmon
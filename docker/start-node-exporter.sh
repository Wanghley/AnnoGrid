#!/bin/bash
# start-node-exporter.sh

NODE_NAME=${1:-$(hostname)}

echo "Starting node-exporter for node: $NODE_NAME"

mkdir -p /var/lib/node_exporter/textfile_collector

docker run -d \
  --name=node-exporter-$NODE_NAME \
  --restart=always \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  -v "/etc/localtime:/etc/localtime:ro" \
  -v "/var/lib/node_exporter/textfile_collector:/host/var/lib/node_exporter/textfile_collector" \
  --cap-add=SYS_TIME \
  -l "com.annogrid.service=monitoring" \
  -l "com.annogrid.component=node-exporter" \
  -l "com.annogrid.node=$NODE_NAME" \
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

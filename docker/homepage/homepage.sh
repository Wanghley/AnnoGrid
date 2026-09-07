#!/bin/bash
#==============================================================================
# AnnoGrid Homepage Stats Generator
# Queries Prometheus + Docker API + Jellyfin → writes public/stats.json
#
# Cron (every 5 min on anno-app):
#   */5 * * * * /home/pi/AnnoGrid/docker/application-server/homepage/homepage.sh
#==============================================================================

#==============================================================================
# Config
#==============================================================================
OUTPUT_DIR="$(dirname "$0")/public"
OUTPUT_FILE="$OUTPUT_DIR/stats.json"

PROMETHEUS_URL="http://100.85.193.50:9090"

JELLYFIN_URL="http://localhost:8096"
JELLYFIN_KEY="${HOMEPAGE_VAR_JELLYFIN_KEY}"

# Prometheus scrape instance labels (from prometheus.yml)
INST_APP="100.67.194.10:9100"
INST_AI="100.85.193.50:9100"
INST_NAS="100.114.225.52:9100"
INST_GW="100.101.178.87:9100"

# Docker socket proxy hosts (port 2375)
DOCKER_AI="100.85.193.50"
DOCKER_NAS="100.114.225.52"
DOCKER_GW="100.101.178.87"

#==============================================================================
# Helpers
#==============================================================================
# Query Prometheus; returns value or "0"
prom() {
    curl -sf -G "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$1" \
        2>/dev/null \
    | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null \
    || echo "0"
}

# awk handles scientific notation from Prometheus (bc does not)
fmt_bytes() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1099511627776) printf "%.2f TB", b / 1099511627776
        else if (b >= 1073741824) printf "%.1f GB", b / 1073741824
        else printf "%.0f MB", b / 1048576
    }'
}

fmt_pct() {
    awk -v used="${1:-0}" -v total="${2:-0}" 'BEGIN {
        if (total > 0) printf "%.1f%%", used * 100 / total
        else printf "N/A"
    }'
}

fmt_uptime() {
    local boot="${1:-0}"
    awk -v now="$(date +%s)" -v boot="${boot%.*}" 'BEGIN {
        s = (now > boot) ? now - boot : 0
        printf "%dd %dh", int(s / 86400), int((s % 86400) / 3600)
    }'
}

fmt_cpu() {
    awk -v v="${1:-0}" 'BEGIN { printf "%.1f%%", (v+0 > 0 ? v+0 : 0) }'
}

# Build a node JSON block (no closing brace — caller appends container fields)
node_block() {
    local key="$1" inst="$2"
    local cpu ram_used ram_total disk_used disk_total boot

    cpu=$(prom       "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\",instance=\"$inst\"}[5m])) * 100)")
    ram_used=$(prom  "node_memory_MemTotal_bytes{instance=\"$inst\"} - node_memory_MemAvailable_bytes{instance=\"$inst\"}")
    ram_total=$(prom "node_memory_MemTotal_bytes{instance=\"$inst\"}")
    disk_used=$(prom "node_filesystem_size_bytes{instance=\"$inst\",mountpoint=\"/\",fstype!~\"tmpfs|overlay\"} - node_filesystem_avail_bytes{instance=\"$inst\",mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}")
    disk_total=$(prom "node_filesystem_size_bytes{instance=\"$inst\",mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}")
    boot=$(prom      "node_boot_time_seconds{instance=\"$inst\"}")

    printf '"%s": {"cpu":"%s","ram":"%s","disk":"%s","uptime":"%s"' \
        "$key" \
        "$(fmt_cpu  "$cpu")" \
        "$(fmt_bytes "$ram_used") / $(fmt_bytes "$ram_total")" \
        "$(fmt_bytes "$disk_used") / $(fmt_bytes "$disk_total")" \
        "$(fmt_uptime "$boot")"
}

#==============================================================================
# Container counts — Docker socket proxy API (accurate; cAdvisor overcounts)
#==============================================================================
docker_running() {
    # $1 = remote host IP (uses port 2375); empty = local docker command
    if [ -z "$1" ]; then
        docker ps -q 2>/dev/null | wc -l | tr -d ' '
    else
        curl -sf "http://$1:2375/containers/json" 2>/dev/null \
            | jq 'length // 0' 2>/dev/null || echo 0
    fi
}

docker_stopped() {
    if [ -z "$1" ]; then
        docker ps -aq --filter "status=exited" --filter "status=dead" 2>/dev/null \
            | wc -l | tr -d ' '
    else
        curl -sf "http://$1:2375/containers/json?all=1" 2>/dev/null \
            | jq '[.[] | select(.State != "running")] | length // 0' 2>/dev/null || echo 0
    fi
}

#==============================================================================
# Jellyfin
#==============================================================================
jf_get() {
    curl -sf "$JELLYFIN_URL$1?api_key=$JELLYFIN_KEY" 2>/dev/null || echo "{}"
}

jf_counts() {
    jf_get "/Items/Counts" | jq '.MovieCount // 0, .EpisodeCount // 0' 2>/dev/null \
        | tr '\n' ' ' || echo "0 0"
}

jf_size() {
    local type="$1"
    jf_get "/Items?IncludeItemTypes=$type&Recursive=true&Fields=Size" \
        | jq '[.Items[].Size // 0] | add // 0' 2>/dev/null || echo 0
}

#==============================================================================
# Collect — nodes
#==============================================================================
mkdir -p "$OUTPUT_DIR"
echo "[ AnnoGrid stats ] $(date)"

BLOCK_APP=$(node_block "anno_app" "$INST_APP")
BLOCK_AI=$(node_block  "anno_ai"  "$INST_AI")
BLOCK_NAS=$(node_block "anno_nas" "$INST_NAS")
BLOCK_GW=$(node_block  "anno_gw"  "$INST_GW")

NAS_TOTAL=$(prom "node_filesystem_size_bytes{instance=\"$INST_NAS\",mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}")
NAS_AVAIL=$(prom "node_filesystem_avail_bytes{instance=\"$INST_NAS\",mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}")
NAS_USED=$(awk -v t="${NAS_TOTAL:-0}" -v a="${NAS_AVAIL:-0}" 'BEGIN { printf "%.0f", t - a }')

#==============================================================================
# Collect — containers (Docker API, not cAdvisor)
#==============================================================================
APP_UP=$(docker_running "");        APP_DOWN=$(docker_stopped "")
AI_UP=$(docker_running  "$DOCKER_AI");   AI_DOWN=$(docker_stopped  "$DOCKER_AI")
NAS_UP=$(docker_running "$DOCKER_NAS");  NAS_DOWN=$(docker_stopped "$DOCKER_NAS")
GW_UP=$(docker_running  "$DOCKER_GW");   GW_DOWN=$(docker_stopped  "$DOCKER_GW")

CLUSTER_RUNNING=$(awk -v a="${APP_UP:-0}" -v b="${AI_UP:-0}" -v c="${NAS_UP:-0}" -v d="${GW_UP:-0}" \
    'BEGIN { print a+b+c+d }')
CLUSTER_STOPPED=$(awk -v a="${APP_DOWN:-0}" -v b="${AI_DOWN:-0}" -v c="${NAS_DOWN:-0}" -v d="${GW_DOWN:-0}" \
    'BEGIN { print a+b+c+d }')
CLUSTER_TOTAL=$(awk -v r="$CLUSTER_RUNNING" -v s="$CLUSTER_STOPPED" 'BEGIN { print r+s }')

#==============================================================================
# Collect — Jellyfin
#==============================================================================
read -r MOVIE_COUNT EP_COUNT <<< "$(jf_counts)"
MOVIE_COUNT=${MOVIE_COUNT:-0}
EP_COUNT=${EP_COUNT:-0}

MOVIE_SIZE=$(jf_size "Movie");    MOVIE_SIZE=${MOVIE_SIZE:-0}
EP_SIZE=$(jf_size "Episode");     EP_SIZE=${EP_SIZE:-0}

#==============================================================================
# Write JSON
#==============================================================================
cat > "$OUTPUT_FILE" << EOF
{
  $BLOCK_APP, "containers_up": "$APP_UP", "containers_down": "$APP_DOWN"},
  $BLOCK_AI,  "containers_up": "$AI_UP",  "containers_down": "$AI_DOWN"},
  $BLOCK_NAS, "storage_used": "$(fmt_bytes "$NAS_USED")", "storage_free": "$(fmt_bytes "$NAS_AVAIL")", "disk_pct": "$(fmt_pct "$NAS_USED" "$NAS_TOTAL")", "containers_up": "$NAS_UP", "containers_down": "$NAS_DOWN"},
  $BLOCK_GW,  "containers_up": "$GW_UP",  "containers_down": "$GW_DOWN"},
  "jellyfin": {
    "movies":  {"count": $MOVIE_COUNT, "storage": "$(fmt_bytes "$MOVIE_SIZE")", "plays": 0, "runtime": "—"},
    "series":  {"episodes": $EP_COUNT, "storage": "$(fmt_bytes "$EP_SIZE")",   "plays": 0, "runtime": "—"}
  },
  "cluster": {
    "running": $CLUSTER_RUNNING,
    "stopped": $CLUSTER_STOPPED,
    "total":   $CLUSTER_TOTAL,
    "hosts":   4
  },
  "timestamp": $(date +%s000)
}
EOF

echo "[ AnnoGrid stats ] Written → $OUTPUT_FILE"

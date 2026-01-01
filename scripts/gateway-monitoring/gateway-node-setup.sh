#!/usr/bin/env bash
#
# gateway-node-setup.sh
#
# Idempotent installer for Raspberry Pi Gateway / Monitoring Node.
# Safety-first:
#  - Does NOT enable networking services (hostapd, dnsmasq, etc) by default.
#  - Holds openssh-server and openssh-client to avoid accidental SSH changes.
#  - Installs node_exporter (downloaded binary) and its systemd unit.
#  - Installs packages incrementally so we don't run out of disk mid-install.
#
# Usage:
#   sudo ./gateway-node-setup.sh
#   sudo SKIP_HEAVY=1 ENABLE_NODE_EXPORTER=1 ./gateway-node-setup.sh
#   sudo DRY_RUN=1 ./gateway-node-setup.sh
#
set -euo pipefail

# ===== Configuration =====
LOGFILE="/var/log/gateway-setup.log"
MIN_FREE_MB=${MIN_FREE_MB:-300}
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-v1.7.2}"
NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-node_exporter}"
NODE_EXPORTER_BIN="${NODE_EXPORTER_BIN:-/usr/local/bin/node_exporter}"
GDIR="${GDIR:-/etc/gateway-setup}"

# Control env flags:
DRY_RUN=${DRY_RUN:-0}                 # 1 = don't perform actions, just echo
SKIP_HEAVY=${SKIP_HEAVY:-0}          # 1 = skip dnsmasq/hostapd group
ENABLE_NODE_EXPORTER=${ENABLE_NODE_EXPORTER:-0}  # 1 = enable+start node_exporter at end

# Package groups (installed incrementally)
PKG_GROUP_BASE=(tmux haveged curl wget git vim moreutils htop jq)
PKG_GROUP_NET=(iproute2 nftables netfilter-persistent iptables-persistent)
PKG_GROUP_MON=(rsync logrotate ethtool dnsutils tcpdump)
PKG_GROUP_SECURITY=(ufw fail2ban wireguard-tools)
PKG_GROUP_HEAVY=(dnsmasq hostapd bridge-utils)

# ===== helpers =====
log() { echo "[$(date -Is)] $*" | tee -a "$LOGFILE"; }
die() { echo "ERROR: $*" | tee -a "$LOGFILE" >&2; exit 1; }
run_or_dry() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] $*"
  else
    eval "$@"
  fi
}

# print usage
usage() {
  cat <<EOF
gateway-node-setup.sh - idempotent gateway/monitoring installer

Environment:
  DRY_RUN=1               Do not change system; only print actions
  SKIP_HEAVY=1            Skip optional heavy packages (dnsmasq, hostapd)
  ENABLE_NODE_EXPORTER=1  Enable and start node_exporter at the end
  NODE_EXPORTER_VERSION=  Override node_exporter version (default ${NODE_EXPORTER_VERSION})

Examples:
  sudo ./gateway-node-setup.sh
  sudo SKIP_HEAVY=1 ENABLE_NODE_EXPORTER=1 ./gateway-node-setup.sh
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

# ===== sanity checks =====
if [ "$(id -u)" -ne 0 ]; then
  die "Must be run as root (sudo)."
fi

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log "==== Gateway setup started: $(date -u +"%Y-%m-%d %H:%M:%SZ") ===="

# recommend tmux
if [ -z "${TMUX:-}" ]; then
  log "Warning: not running inside tmux. Recommended: tmux new -s gateway-install"
fi

FREE_KB=$(df --output=avail / | tail -n1)
FREE_MB=$((FREE_KB/1024))
log "Free space on / : ${FREE_MB} MB (min required ${MIN_FREE_MB} MB)"
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
  die "Free space <$MIN_FREE_MB MB on / — free space before proceeding."
fi

# Hold SSH packages to avoid accidental changes during run
log "Holding openssh-server and openssh-client (to avoid accidental SSH changes)."
run_or_dry "apt-mark hold openssh-server openssh-client >>\"$LOGFILE\" 2>&1 || true"

# ===== apt helpers =====
apt_update() {
  log "apt-get update..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] apt-get update"
    return 0
  fi
  apt-get update -y >>"$LOGFILE" 2>&1 || die "apt-get update failed"
}

install_group() {
  local NAME="$1"; shift
  local PKGS=( "$@" )
  log "Installing group: ${NAME} -> ${PKGS[*]}"
  apt_update
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] apt-get install -y --no-install-recommends ${PKGS[*]}"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}" >>"$LOGFILE" 2>&1 || die "Failed to install group ${NAME}"
  # free cache between groups to reduce disk pressure
  apt-get clean >>"$LOGFILE" 2>&1 || true
}

# ===== perform incremental installs =====
# install base utilities (ensure tmux early)
if ! command -v tmux >/dev/null 2>&1 || [ "$DRY_RUN" -eq 1 ]; then
  install_group "base (tmux+utils)" "${PKG_GROUP_BASE[@]}"
else
  # Ensure base set is present (idempotent)
  install_group "base (rest)" "${PKG_GROUP_BASE[@]}"
fi

# network primitives
install_group "network primitives" "${PKG_GROUP_NET[@]}"

# monitoring & admin utils
install_group "monitoring utils" "${PKG_GROUP_MON[@]}"

# security tools
install_group "security tools" "${PKG_GROUP_SECURITY[@]}"

# optional heavy packages
if [ "${SKIP_HEAVY}" -eq 1 ]; then
  log "SKIP_HEAVY=1 — skipping dnsmasq/hostapd group."
else
  install_group "optional heavy (AP/DHCP)" "${PKG_GROUP_HEAVY[@]}"
fi

# ===== journald limits (keep logs small) =====
log "Applying journald limits..."
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[DRY RUN] write /etc/systemd/journald.conf.d/00-gateway-size.conf"
else
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/00-gateway-size.conf <<'EOF'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=50M
EOF
  systemctl daemon-reload
  systemctl restart systemd-journald || log "systemd-journald restart returned non-fatal status"
fi

# ===== node_exporter installer =====
install_node_exporter() {
  if [ -x "$NODE_EXPORTER_BIN" ]; then
    log "node_exporter binary already exists at $NODE_EXPORTER_BIN"
    return 0
  fi

  # map dpkg arch to node_exporter archive naming
  ARCH="$(dpkg --print-architecture || true)"
  case "$ARCH" in
    armhf) ARCH_TAG="armv7" ;;    # node_exporter provides armv7 for armhf Pi builds
    arm64) ARCH_TAG="arm64" ;;
    amd64) ARCH_TAG="amd64" ;;
    i386) ARCH_TAG="386" ;;
    *) ARCH_TAG="$ARCH" ;;
  esac

  TAR="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH_TAG}.tar.gz"
  URL="https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}/${TAR}"
  log "Downloading node_exporter ${NODE_EXPORTER_VERSION} (${ARCH_TAG}) from ${URL}"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] curl -fsSLo /tmp/${TAR} ${URL}"
    return 0
  fi

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' RETURN
  if ! curl -fsSLo "$TMPDIR/$TAR" "$URL"; then
    log "Download failed from $URL"
    return 1
  fi

  tar -xzf "$TMPDIR/$TAR" -C "$TMPDIR"
  BIN_SRC="$(find "$TMPDIR" -type f -name node_exporter -print -quit)"
  if [ -z "$BIN_SRC" ]; then
    log "Binary not found in archive; skipping node_exporter install"
    return 1
  fi

  install -m 0755 "$BIN_SRC" "$NODE_EXPORTER_BIN"
  if ! id -u "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
    useradd --no-create-home --shell /usr/sbin/nologin --system "$NODE_EXPORTER_USER" || true
  fi

  # systemd unit
  cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  log "node_exporter installed at $NODE_EXPORTER_BIN and systemd unit created."
  if [ "${ENABLE_NODE_EXPORTER:-0}" -eq 1 ]; then
    systemctl enable --now node_exporter
    log "node_exporter enabled and started."
  else
    log "node_exporter not enabled automatically (set ENABLE_NODE_EXPORTER=1 to enable)."
  fi
}

install_node_exporter || log "node_exporter installation failed or skipped"

# ===== create helper README and notes =====
mkdir -p "$GDIR"
cat > "$GDIR/README" <<'EOF'
Gateway / Monitoring Node - README

Installed components (selected):
 - node_exporter (Prometheus)
 - nftables, netfilter-persistent, iptables-persistent
 - ufw, fail2ban, wireguard-tools
 - monitoring/admin tools: rsync, tcpdump, ethtool, logrotate
 - optional: dnsmasq, hostapd (if SKIP_HEAVY not set)

Safety notes:
 - The script does NOT enable/alter network services that can drop SSH by default.
 - SSH packages were held during the run. To allow SSH upgrades later:
     sudo apt-mark unhold openssh-server openssh-client
 - Keep a second SSH session open when testing firewall/network changes.
EOF

# ===== final reporting =====
log "Installed packages summary (selected):"
dpkg -l | awk '/^ii/ {print $2 " " $3}' | grep -E "$(printf '%s|' "${PKG_GROUP_BASE[@]}" "${PKG_GROUP_NET[@]}" "${PKG_GROUP_MON[@]}" "${PKG_GROUP_SECURITY[@]}" "${PKG_GROUP_HEAVY[@]}" | sed 's/|$//')" || true

log "Final free space:"
df -h / | tee -a "$LOGFILE"

log "==== Gateway setup finished: $(date -u +"%Y-%m-%d %H:%M:%SZ") ===="
log "Notes:
 - The script DID NOT enable or start hostapd/dnsmasq by default.
 - To allow SSH package upgrades: sudo apt-mark unhold openssh-server openssh-client
 - See $LOGFILE for detailed logs.
"
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
#   sudo ./gateway-node-setup.sh            # default run (installs groups, skips heavy packages)
#   sudo SKIP_HEAVY=1 ./gateway-node-setup.sh   # skip dnsmasq/hostapd
#   sudo ENABLE_NODE_EXPORTER=1 ./gateway-node-setup.sh  # auto-enable node_exporter at the end
#   sudo DRY_RUN=1 ./gateway-node-setup.sh    # print actions but don't change system
#
set -euo pipefail

### Configuration (tweak if you must)
LOGFILE="/var/log/gateway-setup.log"
MIN_FREE_MB=${MIN_FREE_MB:-300}
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-v1.7.2}"
NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-node_exporter}"
NODE_EXPORTER_BIN="${NODE_EXPORTER_BIN:-/usr/local/bin/node_exporter}"
GDIR="${GDIR:-/etc/gateway-setup}"
# env control
DRY_RUN=${DRY_RUN:-0}
SKIP_HEAVY=${SKIP_HEAVY:-0}       # if 1, skip dnsmasq & hostapd install
ENABLE_NODE_EXPORTER=${ENABLE_NODE_EXPORTER:-0} # if 1, enable+start node_exporter at end

# Package groups (incremental)
PKG_GROUP_BASE=(tmux haveged curl wget git vim moreutils htop jq)
PKG_GROUP_NET=(iproute2 nftables netfilter-persistent iptables-persistent)
PKG_GROUP_MON=(rsync logrotate ethtool dnsutils tcpdump)
PKG_GROUP_SECURITY=(ufw fail2ban wireguard-tools)
PKG_GROUP_HEAVY=(dnsmasq hostapd bridge-utils)

# helper: log (tee to logfile)
log() {
  echo "$@" | tee -a "$LOGFILE"
}

die() {
  echo "ERROR: $*" | tee -a "$LOGFILE" >&2
  exit 1
}

dryrun() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] $*"
  else
    eval "$@"
  fi
}

# show usage
usage() {
  cat <<EOF
gateway-node-setup.sh - idempotent gateway/monitoring installer

Environment variables:
  MIN_FREE_MB=300              Minimum free MB required before running
  SKIP_HEAVY=1                 Skip heavy/optional packages (dnsmasq, hostapd)
  ENABLE_NODE_EXPORTER=1       Enable+start node_exporter after install
  DRY_RUN=1                    Do not change system; print actions only
  NODE_EXPORTER_VERSION=...    Override node_exporter release (default: ${NODE_EXPORTER_VERSION})

Examples:
  sudo ./gateway-node-setup.sh
  sudo SKIP_HEAVY=1 ENABLE_NODE_EXPORTER=1 ./gateway-node-setup.sh

EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

# must be root
if [ "$(id -u)" -ne 0 ]; then
  die "This script must be run as root (sudo)."
fi

# ensure log file
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log "==== Gateway setup started: $(date -u +"%Y-%m-%d %H:%M:%SZ") ===="

# check tmux available / recommend
if ! command -v tmux >/dev/null 2>&1; then
  log "tmux not found. Will install tmux early to provide a lifeline."
fi
if [ -z "${TMUX:-}" ]; then
  log "Warning: running outside tmux. Recommended: tmux new -s gateway-install"
fi

# disk check
FREE_KB=$(df --output=avail / | tail -n1)
FREE_MB=$((FREE_KB/1024))
log "Free space on / : ${FREE_MB} MB (min required ${MIN_FREE_MB} MB)"
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
  die "Free space <$MIN_FREE_MB MB on / — please free space before running this script."
fi

# hold SSH packages to avoid accidental changes during install
log "Holding openssh-server and openssh-client (will not allow upgrades during run)."
dryrun "apt-mark hold openssh-server openssh-client >>\"$LOGFILE\" 2>&1 || true"

# helper to apt-install one group at a time (idempotent)
install_group() {
  local -r NAME="$1"
  shift
  local -r PKGS=( "$@" )
  log "Installing group: ${NAME} -> ${PKGS[*]}"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] apt-get update && apt-get install -y ${PKGS[*]}"
    return 0
  fi
  apt-get update -y >>"$LOGFILE" 2>&1 || die "apt-get update failed"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}" >>"$LOGFILE" 2>&1 || die "Failed to install group ${NAME}"
  log "Group ${NAME} installed successfully."
  # small cleanup after group install to reclaim space
  apt-get clean >>"$LOGFILE" 2>&1 || true
}

# install tmux early (safety)
if ! command -v tmux >/dev/null 2>&1; then
  install_group "base (tmux+utils)" "${PKG_GROUP_BASE[@]}"
fi

# install remaining base utils (some may have been installed above)
install_group "base (rest)" "${PKG_GROUP_BASE[@]}"

# install networking primitives
install_group "network primitives" "${PKG_GROUP_NET[@]}"

# install monitoring & admin utilities
install_group "monitoring utils" "${PKG_GROUP_MON[@]}"

# install security tools
install_group "security tools" "${PKG_GROUP_SECURITY[@]}"

# optionally install heavy packages (dnsmasq/hostapd)
if [ "${SKIP_HEAVY}" -eq 1 ]; then
  log "SKIP_HEAVY=1 set — skipping heavy/optional packages (dnsmasq, hostapd)."
else
  install_group "optional heavy (AP/DHCP)" "${PKG_GROUP_HEAVY[@]}"
fi

# apply journald limits
log "Applying journald limits to keep logs small."
dryrun "mkdir -p /etc/systemd/journald.conf.d"
cat > /etc/systemd/journald.conf.d/00-gateway-size.conf <<'EOF'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=50M
EOF
systemctl daemon-reload
systemctl restart systemd-journald || log "journalctl restart returned non-fatal status"

# create gateway-setup dir and README
log "Writing $GDIR/README"
mkdir -p "$GDIR"
cat > "$GDIR/README" <<'EOF'
Gateway / Monitoring Node - README

This node has had gateway & monitoring packages installed, but NO network services
were enabled or automatically started that may alter routing or drop SSH.

See /var/log/gateway-setup.log for installer details.
EOF

# node_exporter installer function
install_node_exporter() {
  if [ -x "$NODE_EXPORTER_BIN" ]; then
    log "node_exporter already present at $NODE_EXPORTER_BIN"
    return 0
  fi

  # determine arch mapping
  ARCH="$(dpkg --print-architecture || true)"
  case "$ARCH" in
    armhf) ARCH_TAG="armv7" ;;   # use armv7 tarball for armhf/armv7l Pis
    arm64) ARCH_TAG="arm64" ;;
    amd64) ARCH_TAG="amd64" ;;
    i386) ARCH_TAG="386" ;;
    *) ARCH_TAG="$ARCH" ;;
  esac

  TAR="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH_TAG}.tar.gz"
  URL="https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}/${TAR}"
  log "Downloading node_exporter ${NODE_EXPORTER_VERSION} for ${ARCH} (archive: ${TAR})"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY RUN] curl -fsSLo /tmp/${TAR} ${URL}"
    return 0
  fi

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' RETURN
  if ! curl -fsSLo "$TMPDIR/$TAR" "$URL"; then
    log "Failed to download node_exporter from $URL — skipping node_exporter install."
    return 1
  fi

  tar -xzf "$TMPDIR/$TAR" -C "$TMPDIR"
  BIN_SRC="$(find "$TMPDIR" -type f -name node_exporter -print -quit)"
  if [ -z "$BIN_SRC" ]; then
    log "node_exporter binary not found in the downloaded archive — skipping."
    return 1
  fi

  install -m 0755 "$BIN_SRC" "$NODE_EXPORTER_BIN"
  # create user
  if ! id -u "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
    useradd --no-create-home --shell /usr/sbin/nologin --system "$NODE_EXPORTER_USER" || true
  fi

  # write systemd unit
  cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
Type=simple
ExecStart=${NODE_EXPORTER_BIN} --web.listen-address=0.0.0.0:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  log "node_exporter installed at ${NODE_EXPORTER_BIN}. Manual start: sudo systemctl start node_exporter"
  if [ "${ENABLE_NODE_EXPORTER:-0}" -eq 1 ]; then
    systemctl enable --now node_exporter
    log "node_exporter enabled and started."
  else
    log "node_exporter not enabled automatically (set ENABLE_NODE_EXPORTER=1 to enable)."
  fi
}

# install node_exporter
install_node_exporter || log "node_exporter installation failed or skipped"

# Summary of installed packages
log "Installed packages summary (selected):"
dpkg -l | awk '/^ii/ {print $2 " " $3}' | grep -E "$(printf '%s|' "${PKG_GROUP_BASE[@]}" "${PKG_GROUP_NET[@]}" "${PKG_GROUP_MON[@]}" "${PKG_GROUP_SECURITY[@]}" "${PKG_GROUP_HEAVY[@]}" | sed 's/|$//')" || true

# Final free space check
df -h / | tee -a "$LOGFILE"

log "==== Gateway setup finished: $(date -u +"%Y-%m-%d %H:%M:%SZ") ===="
log "Notes:
 - The script DID NOT enable or start network services that could drop SSH (hostapd, dnsmasq).
 - To allow SSH package upgrades later: sudo apt-mark unhold openssh-server openssh-client
 - If DRY_RUN=1 was set, no changes were made.
 - See $LOGFILE for details."
#!/usr/bin/env bash
#
# gateway-node-setup.sh
#
# Idempotent installer for a Raspberry Pi "Gateway / Monitoring" node.
# Safety-first defaults:
#  - Does NOT enable networking services (hostapd, dnsmasq, etc).
#  - Holds openssh-server and openssh-client to avoid accidental SSH changes.
#  - Requires MIN_FREE_MB on / (default 300 MB).
#  - Installs node_exporter (Prometheus exporter) and a systemd unit.
#
# Run as root: sudo ./gateway-node-setup.sh
#
set -euo pipefail

LOGFILE="/var/log/gateway-setup.log"
MIN_FREE_MB=300
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-v1.7.2}"  # change if you want a different release
NODE_EXPORTER_USER="node_exporter"
NODE_EXPORTER_BIN="/usr/local/bin/node_exporter"
GDIR="/etc/gateway-setup"
PKGS_COMMON=(
  iproute2
  iptables
  nftables
  netfilter-persistent
  iptables-persistent
  dnsmasq
  hostapd
  bridge-utils
  haveged
  ufw
  fail2ban
  wireguard-tools
  python3
  python3-pip
  python3-venv
  git
  curl
  wget
  vim
  moreutils
  htop
  jq
  rsync
  logrotate
  ethtool
  dnsutils
  tcpdump
  tmux
)

# helper: log
echo "==== Gateway setup started: $(date -u +"%Y-%m-%d %H:%M:%SZ") ====" | tee -a "$LOGFILE"

die() {
  echo "ERROR: $*" | tee -a "$LOGFILE" >&2
  exit 1
}

# must be root
if [ "$(id -u)" -ne 0 ]; then
  die "This script must be run as root (sudo)."
fi

# ensure we have a tmux lifeline
if ! command -v tmux >/dev/null 2>&1; then
  echo "Installing tmux for session safety..." | tee -a "$LOGFILE"
  DEBIAN_FRONTEND=noninteractive apt-get update -y >>"$LOGFILE" 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >>"$LOGFILE" 2>&1 || die "Failed to install tmux"
fi

if [ -z "${TMUX:-}" ]; then
  echo "WARNING: It's recommended to run inside tmux. Start one with: tmux new -s gateway-install" | tee -a "$LOGFILE"
fi

# disk space sanity
FREE_KB=$(df --output=avail / | tail -n1)
FREE_MB=$((FREE_KB/1024))
echo "Free space on / : ${FREE_MB} MB" | tee -a "$LOGFILE"
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
  die "Free space <$MIN_FREE_MB MB on / — free space before proceeding."
fi

# hold SSH packages to avoid accidental changes during install
echo "Holding openssh-server and openssh-client to avoid accidental SSH changes" | tee -a "$LOGFILE"
apt-mark hold openssh-server openssh-client >>"$LOGFILE" 2>&1 || true

# update & safe upgrade userland packages
echo "Updating package lists..." | tee -a "$LOGFILE"
DEBIAN_FRONTEND=noninteractive apt-get update -y >>"$LOGFILE" 2>&1 || die "apt-get update failed"

echo "Performing safe upgrade (userland only)..." | tee -a "$LOGFILE"
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >>"$LOGFILE" 2>&1 || die "apt-get upgrade failed"

# install core packages
echo "Installing packages: ${PKGS_COMMON[*]}" | tee -a "$LOGFILE"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS_COMMON[@]}" >>"$LOGFILE" 2>&1 || die "Package installation failed"

# clean apt cache
echo "Cleaning apt cache..." | tee -a "$LOGFILE"
apt-get clean >>"$LOGFILE" 2>&1 || true

# journald limits
echo "Applying journald size limits..." | tee -a "$LOGFILE"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/00-gateway-size.conf <<'EOF'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=50M
EOF
systemctl daemon-reload
systemctl restart systemd-journald || echo "systemd-journald restart returned non-zero (non-fatal)" | tee -a "$LOGFILE"

# ensure gateway setup dir and README
mkdir -p "$GDIR"
cat > "$GDIR"/README <<'EOF'
Gateway / Monitoring Node - README
----------------------------------

This node has had gateway & monitoring packages installed, but NO network services
were enabled or automatically started that may alter routing or drop SSH.

Files and notes:
- /var/log/gateway-setup.log  : installer log
- /etc/gateway-setup/README    : this file
- node_exporter systemd unit at /etc/systemd/system/node_exporter.service (if installed)
- node_exporter binary at /usr/local/bin/node_exporter (if installed)

Important safety notes:
- APT package upgrades for SSH are held. To allow SSH upgrades later:
    sudo apt-mark unhold openssh-server openssh-client

- Do NOT enable or start hostapd, dnsmasq, or networking services until tested
  locally or you have a recovery path (Tailscale, second SSH session, serial console).

- Recommended test workflow for network changes:
  1. Keep 2 SSH sessions open.
  2. Make temporary rules and test (see nftables example in this README).
  3. If OK, make persistent and enable.

For detailed guidance and examples see the full README.md shipped alongside this script.
EOF

# NODE_EXPORTER installation (downloaded binary)
install_node_exporter() {
  if [ -x "$NODE_EXPORTER_BIN" ]; then
    echo "node_exporter already installed at $NODE_EXPORTER_BIN" | tee -a "$LOGFILE"
    return 0
  fi

  echo "Installing Prometheus node_exporter ${NODE_EXPORTER_VERSION}..." | tee -a "$LOGFILE"
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' RETURN

  ARCH="$(dpkg --print-architecture)"   # typically armhf on RPi
  case "$ARCH" in
    armhf) ARCH_TAG="armv6l" ;;   # node_exporter uses armv6l for armhf builds
    arm64) ARCH_TAG="arm64" ;;
    amd64) ARCH_TAG="amd64" ;;
    i386) ARCH_TAG="386" ;;
    *) ARCH_TAG="$ARCH" ;;
  esac

  TAR="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH_TAG}.tar.gz"
  URL="https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}/${TAR}"

  echo "Downloading $URL" | tee -a "$LOGFILE"
  if ! curl -fsSLo "$TMPDIR/$TAR" "$URL"; then
    echo "Failed to download node_exporter from $URL. Skipping node_exporter install." | tee -a "$LOGFILE"
    return 1
  fi

  tar -xzf "$TMPDIR/$TAR" -C "$TMPDIR"
  BIN_SRC=$(find "$TMPDIR" -maxdepth 2 -type f -name node_exporter -print -quit)
  if [ -z "$BIN_SRC" ]; then
    echo "node_exporter binary not found in archive. Skipping." | tee -a "$LOGFILE"
    return 1
  fi

  install -m 0755 "$BIN_SRC" "$NODE_EXPORTER_BIN"
  # create user and systemd unit
  if ! id -u "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
    useradd --no-create-home --shell /usr/sbin/nologin --system "$NODE_EXPORTER_USER" || true
  fi

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
  # Do NOT enable/start automatically; leave it disabled for manual start after testing
  echo "node_exporter installed at ${NODE_EXPORTER_BIN}. To start manually:" | tee -a "$LOGFILE"
  echo "  sudo systemctl start node_exporter" | tee -a "$LOGFILE"
  echo "To enable at boot (only after you are ready):" | tee -a "$LOGFILE"
  echo "  sudo systemctl enable --now node_exporter" | tee -a "$LOGFILE"
}

install_node_exporter || echo "node_exporter installation step failed or skipped" | tee -a "$LOGFILE"

# summary: list installed packages from our list
echo "Installed packages (from list):" | tee -a "$LOGFILE"
for p in "${PKGS_COMMON[@]}"; do
  dpkg -l "$p" >/dev/null 2>&1 && echo " - $p" | tee -a "$LOGFILE" || echo " - $p (not installed)" | tee -a "$LOGFILE"
done

# Final free space check
df -h / | tee -a "$LOGFILE"

echo "==== Gateway setup finished: $(date -u +"%Y-%m-%d %H:%M:%SZ") ====" | tee -a "$LOGFILE"
echo "NOTES:
 - The script DID NOT enable or change network services that might drop SSH.
 - Test network changes carefully and keep a second SSH session open.
 - To remove SSH hold: sudo apt-mark unhold openssh-server openssh-client
 - See /etc/gateway-setup/README and README.md for next steps and examples.
" | tee -a "$LOGFILE"

exit 0

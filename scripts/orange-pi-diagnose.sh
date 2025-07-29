#!/bin/bash

echo "==== ORANGE PI DIAGNOSTIC REPORT ===="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo ""

echo "==== SYSTEM INFO ===="
uname -a
echo ""

echo "==== CPU & TEMP ===="
lscpu | grep 'Model name'
vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp
echo ""

echo "==== MEMORY USAGE ===="
free -h
echo ""

echo "==== DISK USAGE ===="
df -h
echo ""

echo "==== NETWORK INTERFACES ===="
ip link show
echo ""
ip a
echo ""

echo "==== DEFAULT ROUTE ===="
ip route show
echo ""

echo "==== DNS ===="
cat /etc/resolv.conf
echo ""

echo "==== WIFI STATUS (wlan0) ===="
iw dev wlan0 link || echo "wlan0: not associated"
echo ""

echo "==== SCANNING WIFI NETWORKS ===="
iw dev wlan0 scan | grep SSID | sort -u
echo ""

echo "==== WIFI POWER SAVE ===="
iw dev wlan0 get power_save
echo ""

echo "==== INTERNET REACHABILITY ===="
ping -c 3 8.8.8.8 && echo "Internet: OK" || echo "Internet: FAIL"
ping -c 3 google.com && echo "DNS: OK" || echo "DNS: FAIL"
echo ""

echo "==== SYSTEMD NETWORK SERVICES ===="
systemctl is-active NetworkManager && echo "NetworkManager: active" || echo "NetworkManager: inactive"
systemctl is-active wpa_supplicant && echo "wpa_supplicant: active" || echo "wpa_supplicant: inactive"
echo ""

echo "==== LAST 50 SYSTEM LOG LINES ===="
journalctl -xe -n 50
echo ""

echo "==== LAST 50 NETWORK LOG LINES ===="
journalctl -u NetworkManager -n 50 || journalctl -u wpa_supplicant -n 50
echo ""

echo "==== TAILSCALE STATUS (if installed) ===="
command -v tailscale >/dev/null && {
    echo "Tailscale status:"
    tailscale status
    echo ""
    journalctl -u tailscaled -n 30
} || echo "Tailscale not installed."
echo ""

echo "==== DOCKER STATUS (if installed) ===="
command -v docker >/dev/null && {
    docker ps -a
    docker network ls
} || echo "Docker not installed."
echo ""

echo "==== END OF REPORT ===="

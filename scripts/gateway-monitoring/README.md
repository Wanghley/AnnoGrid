# Gateway / Monitoring Node — README

This Raspberry Pi is intended to act as the **Gateway & Monitoring Node** in the AnnoNAS topology:
- Border/egress controller (Tailscale & Cloudflare Tunnel recommended)
- Minimal firewall & NAT (nftables preferred)
- Lightweight monitoring (Prometheus node_exporter)
- Security / audit helpers (fail2ban, ufw as frontend)

**Design goals**
- Safety-first: do not auto-enable network services.
- Lightweight: avoid heavy apps that cause CPU / IO spikes.
- Predictable: small set of well-tested tools.

---

## What the installer did
- Installed packages: nftables, iptables persistence, dnsmasq, hostapd, fail2ban, ufw, wireguard-tools, monitoring tools (node_exporter), and common utilities.
- Applied journald limits to keep logs from filling disk.
- Held `openssh-server` and `openssh-client` packages to prevent accidental SSH upgrades during initial setup.
- Created `/etc/gateway-setup` with guidance and logs in `/var/log/gateway-setup.log`.
- **Did not** enable `hostapd`, `dnsmasq`, `node_exporter`, or other networking services. You must enable them manually after testing.

---

## Safety checklist — before making network changes

1. **Open two SSH sessions** to the Pi. Keep one idle until final verification.
2. **Work inside `tmux`**: `tmux new -s gateway`
3. **Confirm Tailscale or other out-of-band access** (if configured).
4. **Take a snapshot / backup** of critical config files you will edit.
   - e.g. `sudo cp /etc/nftables.conf /root/nftables.conf.bak`
5. **Temporarily apply rules** (see test workflow below) — do not enable persistence until tested.
6. If a change may block SSH, schedule an automatic rollback:

```bash
   # restart networking in 5 minutes (rollback)
   echo "systemctl restart networking" | at now + 5 minutes
```

If all is good, cancel the job:

```bash
atrm $(atq | awk 'NR==1{print $1}')
```

---

## Minimal nftables test policy (safe to load temporarily)

**Purpose**: allow SSH (22), allow local network, allow established connections, and NAT outbound. This is a *test* — do **not** replace your full policy blindly.

Save as `/tmp/test-nftables.nft`:

```nft
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iifname "lo" accept
    ip saddr 192.168.0.0/16 accept     # adjust to your LAN
    tcp dport { 22, 9100 } accept      # ssh + node_exporter for testing
    icmpv4 type echo-request accept
    counter drop
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    iifname "eth0" oifname "eth1" accept   # adjust as needed
    counter drop
  }
  chain output {
    type filter hook output priority 0; policy accept;
  }
}

table ip nat {
  chain prerouting {
    type nat hook prerouting priority 0; policy accept;
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    oifname "eth0" masquerade
  }
}
```

**Load temporarily**:

```bash
sudo nft -f /tmp/test-nftables.nft
```

**If SSH is lost**: reconnect via second SSH session or Tailscale. If neither, physically access the device (or power-cycle and boot to recovery if available).

When happy:

```bash
sudo cp /tmp/test-nftables.nft /etc/nftables.conf
sudo systemctl enable --now netfilter-persistent
```

---

## node_exporter (Prometheus) usage

* Binary: `/usr/local/bin/node_exporter`
* Systemd unit (installed but NOT enabled): `/etc/systemd/system/node_exporter.service`

Start manually:

```bash
sudo systemctl start node_exporter
sudo systemctl status node_exporter
```

Enable at boot (only after you are confident):

```bash
sudo systemctl enable --now node_exporter
```

Prometheus (central) should scrape `http://<gateway-ip>:9100/metrics`.

---

## Optional: Tailscale & Cloudflare Tunnel

* **Tailscale**: recommended as your out-of-band admin path. Install via Tailscale instructions: `curl -fsSL https://tailscale.com/install.sh | sh` (or use the package repo). Do not remove SSH hold until you confirm Tailscale access works.
* **Cloudflare Tunnel (cloudflared)**: useful for exposing limited web services. Install per Cloudflare docs and create tunnels for specific services only.

> ⚠️ When installing or configuring Tailscale/cloudflared, do not automatically change local firewall rules. Test connectivity first.

---

## How to enable hostapd/dnsmasq safely (if you plan to run AP)

1. Configure hostapd config file (e.g. `/etc/hostapd/hostapd.conf`) but **do not enable**.
2. Run hostapd manually on console and confirm clients can connect and you still have SSH on your other session:

   ```bash
   sudo hostapd /etc/hostapd/hostapd.conf
   ```
3. Configure dnsmasq in `/etc/dnsmasq.d/` and test it by calling `dnsmasq --test`.
4. If all OK, enable with systemctl and keep second SSH session open.

---

## Monitoring layout recommendation

* **Gateway**: node_exporter, light net tests (ping), logs monitoring (fail2ban).
* **App nodes**: run exporters inside container or host (cAdvisor, node_exporter).
* **Storage nodes**: SMART monitoring, ZFS/raid health exporters.
* **Storage of metrics**: central Prometheus server on App Node (not on gateway) with short retention (days).
* **Alerting**: Alertmanager or simple webhook/email alerts for disk, node down, or tunnel down.

---

## Troubleshooting tips

* `df -h` — disk usage; keep root < 60%.
* `journalctl -u node_exporter` — logs for node_exporter service.
* `systemctl status nftables` or `nft list ruleset` — inspect firewall.
* If SSH is unreachable, try second SSH session, Tailscale, or serial/console.

---

## Final checklist before leaving the node unattended

* [ ] Confirm two SSH methods (LAN and Tailscale or second session).
* [ ] node_exporter running and reachable.
* [ ] nftables policy loaded and tested in temporary mode.
* [ ] Journald limits in place.
* [ ] Backups for critical configuration files.
* [ ] Revoke SSH package hold after comfortable: `sudo apt-mark unhold openssh-server openssh-client`

---

## Further help

If you want, I can:

* Provide pre-filled `hostapd` and `dnsmasq` configs tuned to your LAN.
* Produce an nftables policy tailored to your interface names and network ranges.
* Produce a small Ansible playbook to reproduce the same setup on more nodes.

````

---

## Final notes & how I recommend you run this

1. Transfer both files to the Pi:
   ```bash
   scp gateway-node-setup.sh README.md pi@your.pi:/home/pi/
   ssh pi@your.pi
   sudo chmod +x gateway-node-setup.sh
   tmux new -s gateway-install
   sudo ./gateway-node-setup.sh
````

2. Verify disk and services:

   ```bash
   df -h /
   sudo systemctl start node_exporter
   curl -s http://127.0.0.1:9100/metrics | head
   ```

3. Test firewall changes using the **temporary nftables test policy** in the README.

4. When confident, enable `node_exporter` and netfilter persistence, then unhold SSH if desired:

   ```bash
   sudo systemctl enable --now node_exporter
   sudo systemctl enable --now netfilter-persistent
   sudo apt-mark unhold openssh-server openssh-client
   ```

---

If you want, I can now:

* Generate `hostapd` and `dnsmasq` example configs tailored to your LAN and SSID (including a safe test plan).
* Generate a customized nftables policy for your interface names and IP ranges — tell me your interface names (output of `ip -o link`) and your LAN CIDR and I’ll produce it.

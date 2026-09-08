# AnnoGrid Node Inventory & Specifications

**Last Updated**: 2026-09-07  
**Cluster Name**: AnnoGrid Production  
**Location**: Home Infrastructure Lab + OCI (hybrid)  

---

## 🟢 Active Nodes

### 1. Application Server | anno-app-opi3bp-01

**Hardware Specifications:**
```
Device:           Orange Pi 3B+
CPU:              4× ARM Cortex-A53 @ 2.0 GHz (64-bit)
RAM:              2 GB DDR4
Storage:          64 GB SanDisk Extreme microSD (fast)
Network:          Gigabit Ethernet + WiFi 6
Power:            5V/3A USB-C
Connectivity:     Tailscale + Cloudflare
Status:           🟢 Active & Healthy
```

**Network Configuration:**
```
Hostname:         anno-app-opi3bp-01
Local IP:         192.168.1.10/24
Tailscale IP:     100.x.x.x/24
Gateway:          192.168.1.1
DNS:              1.1.1.1, 8.8.8.8
SSH Port:         22 (standard)
SSH Access:       ssh pi@anno-app-opi3bp-01.local
```

**Performance Characteristics:**
```
Idle Power:       ~2-3W
Active Power:     ~8-10W
Max CPU Temp:     65°C (with heatsink)
Available RAM:    ~1.5 GB (after OS)
Available Storage: ~50 GB (after OS/Docker)
Sustained Upload: ~100 Mbps
Sustained Download: ~900 Mbps
```

**Current Services:**
- Docker daemon (containerized workloads)
- Node Exporter (metrics collection)
- Application containers (n8n, twenty-crm, monica, tandoor, obsidian, homarr, portainer, peekaping, homepage)

> **2026-09-07**: PostgreSQL/MariaDB/Redis/MinIO moved off this node to
> `anno-db-oci-01` (see below) — freed up microSD I/O and RAM. App
> containers now reach the DB over Tailscale. See
> [`docs/guides/db-migration-to-oci.md`](../guides/db-migration-to-oci.md).

**Storage Devices:**
```
/ (OS)            - 64 GB microSD
/var/lib/docker   - Container images and volumes
```

**Temperature & Cooling:**
- Aluminum heatsink (passive cooling)
- Mounted in well-ventilated case
- Thermal monitoring via thermal zone

**Maintenance History:**
```
2026-04-21: Initial deployment
```

**OS & Runtime:**
```
OS:               Armbian Bullseye 64-bit
Kernel:           5.15+ (ARM)
Python:           3.9+
Docker:           20.10+
Docker Compose:   v2.x
```

---

### 2. AI/ML Workload Node | anno-ai-jetson-orin-nano-01

**Hardware Specifications:**
```
Device:           NVIDIA Jetson Orin Nano Developer Kit
CPU:              6× ARM Cortex-A78AE @ 3.5 GHz (ARMv8)
GPU:              NVIDIA Orin Nano (40-core CUDA)
RAM:              8 GB LPDDR5X (shared with GPU)
Storage:          128 GB NVMe SSD (internal)
Connectivity:     Gigabit Ethernet + WiFi 6
Power:            USB-C (5V/15W or external PSU recommended)
CUDA Capability:  sm_89 (supports TensorFlow, PyTorch, ONNX)
Status:           🟢 Active & Healthy
```

**Network Configuration:**
```
Hostname:         anno-ai-jetson-orin-nano-01
Local IP:         192.168.1.11/24
Tailscale IP:     100.x.x.x/24
Gateway:          192.168.1.1
DNS:              1.1.1.1, 8.8.8.8
SSH Port:         22 (standard)
SSH Access:       ssh ubuntu@anno-ai-jetson-orin-nano-01.local
```

**Performance Characteristics:**
```
Idle Power:       ~3-5W
Active Power:     ~10-15W (CPU only)
Active Power:     ~15-25W (GPU active)
Max CPU Temp:     70°C
Max GPU Temp:     75°C
Available RAM:    ~6 GB (after OS)
Available Storage: ~100 GB (after OS)
Sustained Upload: ~500 Mbps (with GPU activity)
Sustained Download: ~900 Mbps
GPU Memory:       8GB (unified with CPU)
```

**GPU Specifications:**
```
CUDA Cores:       128 (40-core GPU)
GPU Memory BW:    102.4 GB/s
Max Power (GPU):  15W
Tensor Cores:     Yes (for matrix operations)
INT8 Performance: ~21 TFLOPS
FP32 Performance: ~21 TFLOPS
FP16 Performance: ~42 TFLOPS (with tensor cores)
```

**Current Services:**
- Docker daemon (with GPU support)
- NVIDIA Container Toolkit (GPU acceleration)
- Node Exporter (metrics including GPU)
- AI/ML inference containers

**Storage Devices:**
```
/ (OS + Applications): 128 GB NVMe SSD
/var/lib/docker:      Container data and models
```

**ML Framework Support:**
```
✓ TensorFlow 2.x (with GPU acceleration)
✓ PyTorch (with CUDA 12.2)
✓ ONNX Runtime (optimized for Orin)
✓ OpenCV (with CUDA backends)
✓ JAX (experimental)
✓ CuDNN (NVIDIA acceleration library)
```

**Development Tools:**
```
JetPack:          5.1.2+ (NVIDIA's integrated SDK)
CUDA:             12.2+
cuDNN:            8.6+
TensorRT:         Latest (model optimization)
Docker:           20.10+ (with nvidia-docker)
```

**Cooling & Power:**
- Official NVIDIA cooling case with fan
- Recommended: External 5V/5A power supply (for sustained GPU workloads)
- Thermal throttling at 80°C

**Maintenance History:**
```
2026-04-21: Initial deployment
2026-04-21: CUDA 12.2 verification
```

**OS & Runtime:**
```
OS:               Ubuntu 22.04 LTS for Jetson (ARM64)
Kernel:           5.15+ (custom Jetson kernel)
Python:           3.10+
Docker:           20.10+
Docker Compose:   v2.x
nvidia-docker:    Enabled
```

**Special Monitoring:**
```
nvidia-smi:       GPU monitoring utility
tegrastats:       Real-time Jetson stats (CPU, GPU, RAM, power)
GPU Power:        Monitor via tegrastats
Thermal Zones:    Monitored via /sys/class/thermal/
```

---

### 3. Storage/NAS Node | anno-nas-rpi3bp-01

**Hardware Specifications:**
```
Device:           Raspberry Pi 3 Model B+
CPU:              4× ARM Cortex-A53 @ 1.4 GHz (64-bit)
RAM:              1 GB LPDDR2
Storage:          32 GB SanDisk Ultra microSD (OS)
External Storage: 2× 2TB WD Red Plus USB 3.0 drives
Network:          Gigabit Ethernet + WiFi + Bluetooth
Power:            5.1V/2.5A microUSB (official PSU)
Connectivity:     Tailscale + Cloudflare
Status:           🟢 Active & Healthy
```

**Network Configuration:**
```
Hostname:         anno-nas-rpi3bp-01
Local IP:         192.168.1.12/24
Tailscale IP:     100.x.x.x/24
Gateway:          192.168.1.1
DNS:              1.1.1.1, 8.8.8.8
SSH Port:         22 (standard)
SSH Access:       ssh pi@anno-nas-rpi3bp-01.local
SMB Access:       \\anno-nas-rpi3bp-01\ (Windows/Mac)
NFS Access:       nfs://anno-nas-rpi3bp-01/exports
```

**Performance Characteristics:**
```
Idle Power:       ~4-5W
Active Power:     ~8-12W (with USB drives)
Max CPU Temp:     60°C
Available RAM:    ~700 MB (after OS)
Available Storage: ~4 TB total (2 drives)
USB 3.0 Speed:    ~400 Mbps (theoretical 5 Gbps, Pi limited)
File Transfer:    ~50-100 Mbps (practical with USB3 drives)
Concurrent SMB:   4-6 clients
```

**Storage Architecture:**
```
/dev/mmcblk0      - 32 GB microSD (Raspberry Pi OS + Docker)
/dev/sda1         - 2 TB USB drive 1 (mounted /mnt/storage1)
/dev/sdb1         - 2 TB USB drive 2 (mounted /mnt/storage2)
/var/lib/docker   - Container data (on microSD)
```

**Storage Services:**
- **Samba/SMB**: Windows/Mac network shares
- **NFS**: Linux network file system
- **Docker volumes**: Persistent storage for containers
- **Backup destination**: Automated backups from app node

**Current Services:**
- Docker daemon (storage services)
- Samba server (SMB/CIFS protocol)
- NFS server (Linux file sharing)
- Node Exporter (metrics collection)
- Rsync/backup services

**Shares Configuration:**
```
[media]           - /mnt/storage1/media
[backups]         - /mnt/storage1/backups
[documents]       - /mnt/storage2/documents
[home]            - /mnt/storage2/home
[docker-volumes]  - /var/lib/docker/volumes
```

**Backup Strategy:**
```
Daily incremental backups from anno-app-opi3bp-01
Weekly full backups of critical data
Off-site cloud backup (encrypted) - monthly
Retention: 4 weeks of daily, 3 months of weekly
```

**Maintenance History:**
```
2026-04-21: Initial deployment with 2× 2TB drives
```

**OS & Runtime:**
```
OS:               Raspberry Pi OS Lite Bullseye 64-bit
Kernel:           5.15+ (ARM)
Python:           3.9+
Docker:           20.10+
Docker Compose:   v2.x
Samba:            4.15+
NFS:              4.1+
```

**Health Monitoring:**
```
Disk Space:       Alert at 85% capacity
Temperature:      Monitor via /sys/class/thermal
Power:            Monitor USB voltage stability
SMB Connections:  Monitor active sessions
File Integrity:   Weekly SMART checks on USB drives
```

---

### 4. Gateway & Monitoring Node | anno-gw-mon-rpi3bp-01

**Hardware Specifications:**
```
Device:           Raspberry Pi 3 Model B+
CPU:              4× ARM Cortex-A53 @ 1.4 GHz (64-bit)
RAM:              1 GB LPDDR2
Storage:          32 GB SanDisk Extreme microSD
Network:          Gigabit Ethernet + WiFi + Bluetooth
Power:            5.1V/2.5A microUSB (official PSU)
Connectivity:     Tailscale + Cloudflare Tunnel
Status:           🟢 Active & Healthy
```

**Network Configuration:**
```
Hostname:         anno-gw-mon-rpi3bp-01
Local IP:         192.168.1.13/24
Tailscale IP:     100.x.x.x/24
Gateway:          192.168.1.1
DNS:              1.1.1.1, 8.8.8.8
SSH Port:         22 (standard)
SSH Access:       ssh pi@anno-gw-mon-rpi3bp-01.local
```

**Performance Characteristics:**
```
Idle Power:       ~4-5W
Active Power:     ~7-10W
Max CPU Temp:     60°C
Available RAM:    ~700 MB (after OS)
Available Storage: ~25 GB (after OS/monitoring data)
Monitoring Data:  ~500 MB/month (15s scrape interval)
Retention:        30 days (adjustable)
```

**Monitoring Stack:**

**Prometheus**
```
Scrape Interval:  15 seconds
Retention:        30 days of metrics
Storage:          ~500 MB/month
Targets:          4 nodes + additional exporters
Rules Evaluation: Every 15 seconds
Alert Evaluation: Every 15 seconds
```

**Grafana**
```
Dashboards:       10+ pre-configured
Data Sources:     Prometheus (primary)
Users:            Admin account configured
Authentication:   Local (username/password)
Plugins:          Installed as needed
```

**Alerting**
```
Alert Manager:    Integrated with Prometheus
Notification:     Email, Slack (configurable)
Alert Rules:      60+ pre-defined rules
Escalation:       Automatic to Slack if critical
```

**Network Services:**

**Tailscale VPN Gateway**
```
MagicDNS:         Enabled (*.ts.net)
ACLs:             Restrictive policy configured
Exit Node:        Disabled (security)
SSH Access:       Enabled for management
DERP Relay:       Global (Tailscale-provided)
```

**Cloudflare Tunnel (Argo)**
```
Tunnel Name:      annogrid-tunnel
Ingress Rules:    Multiple service mappings
Status:           Active and healthy
Redundancy:       Single tunnel (upgrade planned)
Domain:           yourdomain.com (Cloudflare DNS)
```

**Current Services:**
- Prometheus (metrics scraper)
- Grafana (visualization and dashboards)
- Alert Manager (alerting system)
- Node Exporter (local node metrics)
- Tailscale daemon (VPN mesh)
- Cloudflare Tunnel (external access)
- Loki (log aggregation) - optional

**Storage Devices:**
```
/ (OS + Monitoring): 32 GB microSD
/var/lib/prometheus: Metrics database (~500 MB/month)
/var/lib/grafana:    Dashboards and config
```

**Monitoring Targets:**
```
anno-app-opi3bp-01:9100         - App node metrics
anno-ai-jetson-orin-nano-01:9100 - AI node metrics
anno-nas-rpi3bp-01:9100         - NAS node metrics
anno-gw-mon-rpi3bp-01:9100      - Gateway node (self)
Docker containers:              - Container metrics
```

**Alert Channels:**
```
Email:   admin@yourdomain.com (critical alerts)
Slack:   #annogrid-alerts (all alerts)
PagerDuty: (optional, for on-call rotation)
```

**Dashboards Available:**
```
✓ Cluster Overview    - All nodes at a glance
✓ Node Details        - Per-node deep dive
✓ Network Health      - Bandwidth and connectivity
✓ Application Status  - Running services
✓ AI Workload Metrics - GPU and model performance
✓ System Capacity     - Trending and forecasting
```

**Maintenance History:**
```
2026-04-21: Initial deployment with monitoring stack
```

**OS & Runtime:**
```
OS:               Raspberry Pi OS Lite Bullseye 64-bit
Kernel:           5.15+ (ARM)
Python:           3.9+
Docker:           20.10+
Docker Compose:   v2.x
Prometheus:       2.40+
Grafana:          9.x+
Tailscale:        Latest
```

**Health Monitoring:**
```
Disk Space:       Alert at 80% capacity
Metrics Storage:  Alert if compression fails
Alert Manager:    Health check every 5 min
Grafana:          Health check every 10 min
Tailscale:        Monitored via MagicDNS
```

---

### 5. Database Server | anno-db-oci-01

**Hardware Specifications:**
```
Device:           Oracle Cloud Infrastructure VPS
CPU:              <OCPU count> (fill in from your OCI shape)
RAM:              <GB> (fill in from your OCI shape)
Storage:          <GB> OCI Block Volume
Network:          OCI VCN + Tailscale overlay
Power:            N/A (cloud-hosted)
Connectivity:     Tailscale only (no public DB ports, no Cloudflare)
Status:           🟡 Provisioning
```

**Network Configuration:**
```
Hostname:         anno-db-oci-01
OCI Public IP:    <fill in> (SSH only — DB ports never exposed here)
Tailscale IP:     100.x.x.x/24
SSH Port:         22
SSH Access:       ssh ubuntu@anno-db-oci-01.<your-tailnet>.ts.net
```

**Role:**
Runs [`docker/core-data/`](../../docker/core-data/README.md) — centralized
PostgreSQL, MariaDB, Redis, CouchDB, and MinIO for every AnnoGrid app stack.
Replaces three previously local DB deployments on `anno-app-opi3bp-01`
(`application-server/docker-compose.db.yml`, retired; `core-data/`'s own
pre-migration local deployment; and `docker/obsidian/`'s local couchdb,
retired 2026-09-08). See
[`docs/guides/db-migration-to-oci.md`](../guides/db-migration-to-oci.md) and
[`nodes/anno-db-oci-01/README.md`](../../nodes/anno-db-oci-01/README.md).

**Current Services:**
- Docker daemon
- PostgreSQL (`postgres_data`)
- MariaDB (`mariadb_data`)
- Redis (`redis_data`)
- CouchDB (`couchdb_data`)
- MinIO (`minio_data`)
- Node Exporter (metrics collection)

**Security:**
```
All DB ports (5432, 3306, 6379, 5984, 9000, 9001) bound to the Tailscale IP only
OCI Security List / NSG: allow only SSH (22) + Tailscale UDP (41641)
No Cloudflare Tunnel — this node is never internet-facing for app traffic
```

**Backup Strategy:**
```
Daily pg_dumpall + mariadb-dump, shipped off-box to anno-nas-rpi3bp-01
Redis: dump.rdb snapshot alongside DB dumps
Retention: match anno-nas-rpi3bp-01's existing policy (4 weeks daily)
```

**Maintenance History:**
```
2026-09-07: Migrated from local anno-app-opi3bp-01 DB stacks
```

**OS & Runtime:**
```
OS:               Ubuntu 22.04 LTS
Docker:           24.0+
Docker Compose:   v2.x
Tailscale:        Latest
```

---

## 🌐 Network Summary

**Local Network (192.168.1.0/24)**
```
Router/Gateway:    192.168.1.1 (TP-Link AX1500)
Switch:            192.168.1.254 (TP-Link TL-SG608, optional)
DHCP Pool:         192.168.1.50-200
Reserved (DHCP):   192.168.1.21-49
AnnoGrid Static:   192.168.1.10-13
Available:         192.168.1.14-20 (for expansion)
```

**Tailscale Network (100.x.x.x/24)**
```
VPN Type:          WireGuard mesh VPN
Encryption:        End-to-end
MagicDNS:          *.ts.net domains
Auto-discovery:    Enabled
Relay Servers:     Global DERP relays
```

**External Access**
```
Provider:          Cloudflare
Tunnel Type:       Argo Tunnel (HTTP/HTTPS)
Domain:            yourdomain.com
SSL/TLS:           Automatic (Cloudflare managed)
DDoS Protection:   Enabled
```

---

## 📊 Cluster Resource Summary

**Total Capacity:**
```
Total CPU:         18 cores (4+6+4+4)
Total RAM:         13 GB (2+8+1+1+1 usable for apps)
Total Storage:     ~4.3 TB (0.064+0.128+4+0.032)
Total Power (Active): ~40-50W
Annual Electricity:   ~$50-70 (at $0.12/kWh)
```

**Usage (Current):**
```
CPU Usage:         15-25% average
RAM Usage:         40-50% average
Storage Usage:     30% (1.3 TB of 4.3 TB)
Network Usage:     ~5-10 Mbps average
Power Usage:       ~35-45W average
```

**Headroom (Available):**
```
CPU:               75-85% available
RAM:               50-60% available
Storage:           2-3 TB available
Network:           990 Mbps available (1Gbps - 10 Mbps)
```

---

## 🔄 Expansion Plan

### Phase 2 (Q3 2026)
- [ ] Add anno-app-opi3bp-02 (redundant app server)
- [ ] Add anno-storage-rpi5-01 (faster storage with Pi 5)
- [ ] Upgrade gateway to Raspberry Pi 5
- [ ] Add redundant monitoring (2nd Prometheus instance)

### Phase 3 (Q4 2026)
- [ ] Kubernetes cluster (lightweight K3s)
- [ ] Service mesh (optional, for learning)
- [ ] Log aggregation at scale (ELK stack)
- [ ] Database replication (PostgreSQL HA)

---

## 📋 Access Methods Cheat Sheet

```bash
# SSH (Local Network)
ssh pi@anno-app-opi3bp-01.local
ssh ubuntu@anno-ai-jetson-orin-nano-01.local
ssh pi@anno-nas-rpi3bp-01.local
ssh pi@anno-gw-mon-rpi3bp-01.local

# SSH (Tailscale - More Secure, and the ONLY way to reach anno-db-oci-01)
ssh pi@100.x.x.x  # Use Tailscale IPs for remote access
ssh ubuntu@anno-db-oci-01.<your-tailnet>.ts.net  # DB node — no local-network path exists

# Monitoring (Local)
http://anno-gw-mon-rpi3bp-01.local:9090      # Prometheus
http://anno-gw-mon-rpi3bp-01.local:3000      # Grafana

# Monitoring (External)
https://monitoring.yourdomain.com              # Prometheus
https://grafana.yourdomain.com                 # Grafana

# Storage Access
\\anno-nas-rpi3bp-01\media                     # SMB (Windows/Mac)
nfs://anno-nas-rpi3bp-01/media                 # NFS (Linux)

# VPN Access
tailscale ip -4   # Show Tailscale IP on any node
```

---

**Last Updated**: 2026-09-07  
**Next Review**: Q4 2026 (quarterly)


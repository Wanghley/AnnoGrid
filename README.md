<!-- PROJECT SHIELDS -->
<a name="readme-top"></a>
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![LinkedIn][linkedin-shield]][linkedin-url]
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/wanghley)

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/Wanghley/AnnoNAS">
    <img src="assets/logo_1024_transparent.png" alt="AnnoNAS Logo" height="150">
  </a>

  <h3 align="center">AnnoNAS: Multi-Node Smart Home & Edge Infrastructure</h3>

  <p align="center">
    AnnoNAS is a modular home/edge computing infrastructure designed to integrate applications, storage, networking, and monitoring across small computing boards.
    <br />
    <a href="https://github.com/Wanghley/AnnoNAS"><strong>Explore the repo »</strong></a>
    <br />
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#general-architecture">General Architecture</a></li>
    <li><a href="#naming-convention">Naming Convention</a></li>
    <li><a href="#hardware-and-roles">Hardware and Roles</a></li>
    <li><a href="#networking">Networking</a></li>
    <li><a href="#monitoring-stack">Monitoring Stack</a></li>
    <li><a href="#built-with">Built With</a></li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>

---

## About The Project

AnnoNAS is a **modular and scalable home/edge infrastructure project** designed for small computing boards such as Orange Pi and Raspberry Pi. It aims to provide:

- **Scalability**: Add nodes dynamically for applications, storage, or monitoring.  
- **Flexibility**: Nodes are separated by functional roles: app server, NAS, gateway, monitoring, backups.  
- **Security**: Secure access with **Tailscale mesh VPN** and **Cloudflare Tunnels** for external ingress.  
- **Observability**: Centralized monitoring using **Prometheus**, **Grafana**, and **Uptime Kuma**.  

The project is suitable for tech enthusiasts, developers, and home lab engineers who want a **cost-effective and manageable multi-node environment**.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## General Architecture

AnnoNAS is structured around **three main types of nodes**:

1. **Application Nodes** – run core services and Docker containers.  
2. **Storage Nodes (NAS)** – manage persistent data and backups.  
3. **Gateway / Monitoring Nodes** – manage network access, VPN, and collect metrics.  

Optional future nodes include backup nodes, database nodes, and edge AI accelerators.  

```
        ┌─────────────────────┐
        │    Tailscale VPN    │
        │   & Cloudflare      │
        │      Gateway        │
        └─────────┬───────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼───┐    ┌────▼────┐   ┌────▼────┐
│ App   │    │ Storage │   │Gateway/ │
│ Node  │    │  (NAS)  │   │Monitor  │
│       │    │  Node   │   │  Node   │
└───────┘    └─────────┘   └─────────┘
```

---

## Naming Convention

Each node is named systematically for **clarity and scalability**:

```
[grid]-[role]-[device]-[id]
```

| Component | Description | Example |
|-----------|-------------|---------|
| grid      | Cluster prefix | `anno` |
| role      | Node function | `app`, `nas`, `gw`, `mon`, `bkp` |
| device    | Hardware model | `opi3b`, `opi3bp`, `rpi3b+` |
| id        | Unique index | `01`, `02` |

Example:
```
anno-app-opi3b-01
```

---

## Hardware and Roles

| Hostname | Hardware | OS | Roles | Description |
|----------|---------|----|-------|-------------|
| anno-app-opi3b-01 | Orange Pi 3B | Armbian | app | Runs Cosmos Cloud, Docker apps: MonicaHQ, N8n, Jellyfin |
| anno-nas-opi3bp-01 | Orange Pi 3B+ | Raspbian + OMV | nas | Storage node with two HDDs, file server |
| anno-gw-mon-rpi3bp-01 | Raspberry Pi 3B+ | Raspbian | gw, mon | Gateway + monitoring stack, Cloudflare, Tailscale, Prometheus, Grafana, Uptime Kuma |

---

## Networking

- **Tailscale Mesh VPN**: Provides secure encrypted connections between all nodes.  
- **Cloudflare Tunnel (Cloudflared)**: Enables secure access to services without exposing ports to the public internet.  
- **Gateway Node**: Central point for network routing and monitoring.  

---

## Monitoring Stack

Monitoring runs on the **gateway node**:

### Components

- **Prometheus** → metrics collection from Node Exporters.  
- **Grafana** → dashboards and visualizations.  
- **Node Exporter** → lightweight agent on each node to expose system metrics.  
- **Uptime Kuma** → monitor availability of services.  

### Node Exporter Deployment

Run on each node:

```bash
#!/bin/bash
NODE_NAME=${1:-$(hostname)}
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
```

### Prometheus Configuration

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "anno-nodes"
    static_configs:
      - targets:
          - "100.x.x.x:9100"  # anno-app-opi3b-01 (Tailscale IP)
          - "100.x.x.x:9100"  # anno-nas-opi3bp-01
          - "100.x.x.x:9100"  # anno-gw-mon-rpi3bp-01
```

---

## Built With

* Docker / Docker Compose
* Prometheus
* Grafana
* Node Exporter
* Uptime Kuma
* Tailscale (mesh VPN)
* Cloudflared (Cloudflare Tunnel)
* Armbian / Raspbian

---

## Getting Started

1. Clone the repo:

```sh
git clone https://github.com/Wanghley/AnnoNAS.git
```

2. Deploy Node Exporter on all nodes:

```sh
cd AnnoNAS/scripts
chmod +x start-node-exporter.sh
./start-node-exporter.sh
```

3. Configure your nodes according to their roles (see Hardware and Roles section)

4. Set up monitoring stack on the gateway node

5. Configure Tailscale VPN for secure inter-node communication

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Usage

### Starting Services

Each node has specific Docker Compose configurations for its role:

- **Application Node**: Run application services
- **NAS Node**: Storage and file sharing services  
- **Gateway/Monitoring Node**: VPN, monitoring, and network services

### Accessing Services

Services are accessible through:
- **Local Network**: Direct IP access for internal services
- **Tailscale VPN**: Secure mesh network access
- **Cloudflare Tunnel**: External access without port forwarding

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Roadmap

- [ ] Add automated node discovery
- [ ] Implement high availability for critical services
- [ ] Add backup automation
- [ ] Integrate edge AI capabilities
- [ ] Create web-based management interface

See the [open issues](https://github.com/Wanghley/AnnoNAS/issues) for a full list of proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contributing

Contributions are what make the open source community amazing! Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## License

Distributed under the MIT License. See `LICENSE.md` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contact

Wanghley Soares Martins - [@wanghley](https://github.com/Wanghley)

Project Link: [https://github.com/Wanghley/AnnoNAS](https://github.com/Wanghley/AnnoNAS)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/Wanghley/AnnoNAS.svg?style=for-the-badge
[contributors-url]: https://github.com/Wanghley/AnnoNAS/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/Wanghley/AnnoNAS.svg?style=for-the-badge
[forks-url]: https://github.com/Wanghley/AnnoNAS/network/members
[stars-shield]: https://img.shields.io/github/stars/Wanghley/AnnoNAS.svg?style=for-the-badge
[stars-url]: https://github.com/Wanghley/AnnoNAS/stargazers
[issues-shield]: https://img.shields.io/github/issues/Wanghley/AnnoNAS.svg?style=for-the-badge
[issues-url]: https://github.com/Wanghley/AnnoNAS/issues
[license-shield]: https://img.shields.io/github/license/Wanghley/AnnoNAS.svg?style=for-the-badge
[license-url]: https://github.com/Wanghley/AnnoNAS/blob/main/LICENSE.md
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/wanghley

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
  <a href="https://github.com/wanghley/anno-grid">
    <img src="assets/logo_1024_transparent.png" alt="AnnoGrid Logo" height="150">
  </a>

  <h3 align="center">AnnoGrid: Affordable Multi-Node Home & Edge Infrastructure</h3>

  <p align="center">
    AnnoGrid is a modular, low-cost, multi-node homelab platform that allows anyone to run a powerful home server, storage, and network monitoring infrastructure using small single-board computers.
    <br />
    <a href="https://github.com/wanghley/anno-grid"><strong>Explore the project »</strong></a>
    <br />
  </p>
</div>

---

## About The Project

AnnoGrid is designed to **democratize homelabs**. Traditional home servers can be expensive, bulky, and power-hungry. AnnoGrid uses **affordable small single-board computers** like Raspberry Pi and Orange Pi to create a **scalable, modular, and efficient cluster**.  

Its goals are to provide:

- **Low-Cost Infrastructure**: Build a home server, NAS, and monitoring stack for the price of a few boards.  
- **Power Efficiency**: Single-board computers consume a fraction of the power of traditional servers.  
- **Scalability**: Start with a few nodes and expand as your needs grow.  
- **Flexibility**: Each node can have a dedicated role—application server, storage, gateway, or monitoring.  
- **Security & Connectivity**: Integrates mesh VPN and Cloudflare Tunnels for safe external access.  
- **Observability**: Built-in monitoring and metrics collection for all nodes and services.  

AnnoGrid is perfect for **tech enthusiasts, home lab builders, students, and developers** who want a hands-on, affordable, and practical environment to learn, experiment, and run small-scale applications.

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

Getting started with AnnoGrid is simple:

1. Acquire one or more small single-board computers (e.g., Orange Pi, Raspberry Pi).  
2. Assign roles to each node (App, NAS, Gateway, Monitoring).  
3. Set up network connectivity via Tailscale and Cloudflare.  
4. Deploy services according to your needs: storage, apps, or monitoring.  
5. Expand your grid as your requirements grow.

AnnoGrid supports **Docker-based deployment**, but can be adapted to other lightweight virtualization or container orchestration platforms.

---

## Roadmap

- Add dedicated backup and database nodes.  
- Integrate edge AI and TinyML workloads.  
- Automate node discovery and metrics collection.  
- Create pre-configured images for fast deployment.  
- Expand community examples and tutorials.

---

## License

This project is licensed under the MIT License.

---

## Contact

Wanghley – [LinkedIn](https://linkedin.com/in/wanghley)  

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/wanghley/anno-grid?style=for-the-badge
[contributors-url]: https://github.com/wanghley/anno-grid/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/wanghley/anno-grid.svg?style=for-the-badge
[forks-url]: https://github.com/wanghley/anno-grid/network/members
[stars-shield]: https://img.shields.io/github/stars/wanghley/anno-grid.svg?style=for-the-badge
[stars-url]: https://github.com/wanghley/anno-grid/stargazers
[issues-shield]: https://img.shields.io/github/issues/wanghley/anno-grid.svg?style=for-the-badge
[issues-url]: https://github.com/wanghley/anno-grid/issues
[license-shield]: https://img.shields.io/github/license/wanghley/anno-grid.svg?style=for-the-badge
[license-url]: https://github.com/wanghley/anno-grid/blob/master/LICENSE
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555

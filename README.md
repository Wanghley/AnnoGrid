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

## Key Benefits

- **Affordable Homelab**: A complete multi-node setup costs far less than a commercial server.  
- **Energy Efficient**: Runs 24/7 with minimal electricity consumption.  
- **Self-Hosted Apps**: Host your own services like home automation, cloud storage, media servers, or workflow automation tools.  
- **Centralized Monitoring**: Gain visibility into system metrics, uptime, and service health across all nodes.  
- **Flexible Architecture**: Mix and match nodes according to your needs—expand with storage, backup, or compute nodes.  
- **Secure Networking**: Tailscale mesh VPN ensures private communication between nodes, while Cloudflare Tunnel secures external access.  

---

## Architecture Overview

AnnoGrid is composed of **multiple small nodes** that work together as a cohesive system:

1. **Application Nodes** – Run your apps and services in containers or lightweight VMs.  
2. **Storage Nodes (NAS)** – Centralized storage for files, backups, and shared resources.  
3. **Gateway & Monitoring Nodes** – Act as a secure network gateway, collecting metrics and monitoring all nodes.  

This architecture allows **easy expansion**, letting you start small and add more nodes as needed. Each node is low-cost, but together they deliver the functionality of a traditional homelab.

---

## Example Node Roles

| Role | Function | Typical Use |
|------|---------|-------------|
| **App Node** | Runs containers for applications | Workflow automation, personal cloud, media server |
| **NAS Node** | Provides storage & backup | File server, shared media libraries, database storage |
| **Gateway Node** | Handles networking & secure ingress | VPN, Cloudflare Tunnels, firewall rules |
| **Monitoring Node** | Collects and visualizes metrics | Prometheus, Grafana dashboards, service uptime |

Each node can serve **multiple roles** depending on hardware capability and project needs.

---

## Why AnnoGrid?

- **Accessible**: Build your homelab using devices you can afford or already have.  
- **Modular**: Add, remove, or re-purpose nodes without affecting the whole system.  
- **Educational**: Learn networking, containerization, monitoring, and system administration hands-on.  
- **Safe**: Built-in security measures let you expose only what you need.  
- **Future-Proof**: Easy to expand with new nodes, services, or even AI and edge computing tasks.  

AnnoGrid is a **practical, low-cost alternative to expensive enterprise hardware**, giving you full control over your home or edge computing environment.

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
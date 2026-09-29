# AnnoGrid Cluster Management Makefile
# Convenient commands for cluster operations

.PHONY: help health status logs update backup deploy test clean

# AI node = ai-jacaranda (Tailscale MagicDNS). Override: make deploy-ai AI_HOST=... AI_USER=...
AI_HOST ?= ai-jacaranda
AI_USER ?= wanghley
AI_DIR  ?= ~/Workspace/AnnoGrid/docker/ai-jetson-orin

help:
	@echo "AnnoGrid Cluster Commands"
	@echo "========================="
	@echo ""
	@echo "Cluster Health:"
	@echo "  make health          - Check health of all nodes"
	@echo "  make status          - Show detailed status of cluster"
	@echo "  make network-test    - Test network connectivity"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs            - Follow logs from all nodes"
	@echo "  make monitoring-dashboard - Show monitoring URLs"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-app      - Deploy app node services"
	@echo "  make deploy-ai       - Deploy AI node services"
	@echo "  make deploy-nas      - Deploy NAS node services"
	@echo "  make deploy-gateway  - Deploy gateway/monitoring services"
	@echo "  make deploy-all      - Deploy all nodes"
	@echo ""
	@echo "Updates:"
	@echo "  make update-app      - Update app node"
	@echo "  make update-ai       - Update AI node"
	@echo "  make update-nas      - Update NAS node"
	@echo "  make update-gateway  - Update gateway node"
	@echo "  make update-all      - Update all nodes"
	@echo ""
	@echo "Backups:"
	@echo "  make backup-configs  - Backup all configurations"
	@echo "  make backup-data     - Backup application data"
	@echo "  make restore-backup  - Restore from backup"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean           - Clean up unused Docker resources"
	@echo "  make cleanup-logs    - Clean old logs"
	@echo ""
	@echo "Access:"
	@echo "  make ssh-app         - SSH to app node"
	@echo "  make ssh-ai          - SSH to AI node"
	@echo "  make ssh-nas         - SSH to NAS node"
	@echo "  make ssh-gateway     - SSH to gateway node"
	@echo ""

# ==========================================
# Health & Status Commands
# ==========================================

health:
	@echo "🔍 Checking cluster health..."
	@bash scripts/cluster/health-check-all.sh

status:
	@echo "📊 Cluster Status"
	@echo "================="
	@echo ""
	@echo "Application Node (anno-app-opi3bp-01):"
	@echo "  SSH: ssh pi@anno-app-opi3bp-01.local"
	@ssh -o StrictHostKeyChecking=no pi@anno-app-opi3bp-01.local "echo '  Uptime:' && uptime && echo '  Docker:' && docker compose ps 2>/dev/null | tail -5" 2>/dev/null || echo "  ❌ Unreachable"
	@echo ""
	@echo "AI Node (anno-ai-jetson-orin-nano-01):"
	@echo "  SSH: ssh ubuntu@anno-ai-jetson-orin-nano-01.local"
	@ssh -o StrictHostKeyChecking=no ubuntu@anno-ai-jetson-orin-nano-01.local "echo '  GPU:' && nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,nounits | head -1" 2>/dev/null || echo "  ❌ Unreachable"
	@echo ""
	@echo "Storage Node (anno-nas-rpi3bp-01):"
	@echo "  SSH: ssh pi@anno-nas-rpi3bp-01.local"
	@ssh -o StrictHostKeyChecking=no pi@anno-nas-rpi3bp-01.local "df -h /mnt/storage* | grep -v Filesystem" 2>/dev/null || echo "  ❌ Unreachable"
	@echo ""
	@echo "Gateway Node (anno-gw-mon-rpi3bp-01):"
	@echo "  SSH: ssh pi@anno-gw-mon-rpi3bp-01.local"
	@ssh -o StrictHostKeyChecking=no pi@anno-gw-mon-rpi3bp-01.local "docker compose ps | tail -10" 2>/dev/null || echo "  ❌ Unreachable"

network-test:
	@echo "🌐 Testing network connectivity..."
	@bash scripts/cluster/network-test.sh

# ==========================================
# SSH Access Commands
# ==========================================

ssh-app:
	ssh pi@anno-app-opi3bp-01.local

ssh-ai:
	ssh $(AI_USER)@$(AI_HOST)

ssh-nas:
	ssh pi@anno-nas-rpi3bp-01.local

ssh-gateway:
	ssh pi@anno-gw-mon-rpi3bp-01.local

# ==========================================
# Deployment Commands
# ==========================================

deploy-app:
	@echo "🚀 Deploying app node services..."
	@ssh pi@anno-app-opi3bp-01.local "cd ~/annogrid && docker compose pull && docker compose up -d"

deploy-ai:
	@echo "🚀 Deploying AI node services (LiteLLM + Postgres + Open WebUI)..."
	@ssh $(AI_USER)@$(AI_HOST) "cd $(AI_DIR)/litellm && ./setup.sh"

deploy-nas:
	@echo "🚀 Deploying NAS node services..."
	@ssh pi@anno-nas-rpi3bp-01.local "cd ~/annogrid && docker compose pull && docker compose up -d"

deploy-gateway:
	@echo "🚀 Deploying gateway/monitoring services..."
	@ssh pi@anno-gw-mon-rpi3bp-01.local "cd ~/annogrid && docker compose pull && docker compose up -d"

deploy-all: deploy-app deploy-ai deploy-nas deploy-gateway
	@echo "✅ All nodes deployed"

# ==========================================
# Update Commands
# ==========================================

update-app:
	@echo "📦 Updating app node..."
	@ssh pi@anno-app-opi3bp-01.local "sudo apt update && sudo apt upgrade -y && docker system prune -a -f"

# Pulls new images for the AI stack only. Deliberately NOT `apt upgrade` (can break the
# JetPack/CUDA stack) and NOT `docker system prune -a` (deletes images of stopped stacks).
# Dangling layers only.
update-ai:
	@echo "📦 Updating AI node stack..."
	@ssh $(AI_USER)@$(AI_HOST) "cd $(AI_DIR)/litellm && docker compose pull && docker compose up -d && docker image prune -f"

update-nas:
	@echo "📦 Updating NAS node..."
	@ssh pi@anno-nas-rpi3bp-01.local "sudo apt update && sudo apt upgrade -y && docker system prune -a -f"

update-gateway:
	@echo "📦 Updating gateway node..."
	@ssh pi@anno-gw-mon-rpi3bp-01.local "sudo apt update && sudo apt upgrade -y && docker system prune -a -f"

update-all: update-app update-ai update-nas update-gateway
	@echo "✅ All nodes updated"

# ==========================================
# Monitoring Commands
# ==========================================

monitoring-dashboard:
	@echo "📊 Monitoring Dashboard URLs"
	@echo "=============================="
	@echo ""
	@echo "Local Network (LAN):"
	@echo "  Prometheus: http://anno-gw-mon-rpi3bp-01.local:9090"
	@echo "  Grafana:    http://anno-gw-mon-rpi3bp-01.local:3000"
	@echo ""
	@echo "Tailscale VPN:"
	@echo "  Prometheus: http://100.x.x.x:9090"
	@echo "  Grafana:    http://100.x.x.x:3000"
	@echo ""
	@echo "External (Cloudflare Tunnel):"
	@echo "  Prometheus: https://monitoring.yourdomain.com"
	@echo "  Grafana:    https://grafana.yourdomain.com"

logs:
	@echo "📋 Cluster Logs"
	@echo "==============="
	@echo ""
	@echo "App Node:"
	@ssh pi@anno-app-opi3bp-01.local "docker compose logs -f" &
	@echo ""
	@echo "Gateway Node:"
	@ssh pi@anno-gw-mon-rpi3bp-01.local "docker compose logs -f" &
	@wait

# ==========================================
# Backup Commands
# ==========================================

backup-configs:
	@echo "💾 Backing up configurations..."
	@bash scripts/cluster/backup-all.sh

backup-data:
	@echo "💾 Backing up application data..."
	@ssh pi@anno-nas-rpi3bp-01.local "sudo /backup/backup-volumes.sh"

restore-backup:
	@echo "⚠️  Restore from backup (interactive)"
	@bash backup/restore-procedures/restore-from-backup.sh

# ==========================================
# Maintenance Commands
# ==========================================

clean:
	@echo "🧹 Cleaning Docker resources on all nodes..."
	@for node in anno-app-opi3bp-01 anno-ai-jetson-orin-nano-01 anno-nas-rpi3bp-01 anno-gw-mon-rpi3bp-01; do \
		echo "Cleaning $$node..."; \
		ssh pi@$$node.local "docker system prune -a -f" 2>/dev/null || ssh ubuntu@$$node.local "docker system prune -a -f" 2>/dev/null || true; \
	done
	@echo "✅ Cleanup complete"

cleanup-logs:
	@echo "🧹 Cleaning old logs..."
	@for node in anno-app-opi3bp-01 anno-ai-jetson-orin-nano-01 anno-nas-rpi3bp-01 anno-gw-mon-rpi3bp-01; do \
		echo "Cleaning logs on $$node..."; \
		ssh pi@$$node.local "find /var/lib/docker/containers -name '*.log' -mtime +7 -delete" 2>/dev/null || true; \
	done
	@echo "✅ Log cleanup complete"

# ==========================================
# Testing Commands
# ==========================================

test:
	@echo "🧪 Running cluster tests..."
	@bash scripts/cluster/health-check-all.sh
	@bash scripts/cluster/network-test.sh
	@echo "✅ Tests complete"

# ==========================================
# Quick Access URLs
# ==========================================

urls:
	@echo "📍 Quick Access URLs"
	@echo "===================="
	@echo ""
	@echo "Node Access:"
	@echo "  App Node:      http://anno-app-opi3bp-01.local"
	@echo "  AI Node:       http://anno-ai-jetson-orin-nano-01.local"
	@echo "  NAS Node:      \\\\\\\\anno-nas-rpi3bp-01\\\\media (Windows)"
	@echo "  Gateway Node:  http://anno-gw-mon-rpi3bp-01.local"
	@echo ""
	@echo "Homelab Dashboard:"
	@echo "  Homepage:   http://anno-app-opi3bp-01.local:3033"
	@echo ""
	@echo "Monitoring (Local):"
	@echo "  Prometheus: http://anno-gw-mon-rpi3bp-01.local:9090"
	@echo "  Grafana:    http://anno-gw-mon-rpi3bp-01.local:3000"
	@echo ""
	@echo "VPN Access (Tailscale):"
	@echo "  tailscale ip -4  (get your IP)"
	@echo ""
	@echo "External (Cloudflare Tunnel):"
	@echo "  https://monitoring.yourdomain.com"
	@echo "  https://grafana.yourdomain.com"

# ==========================================
# Default target
# ==========================================

.DEFAULT_GOAL := help

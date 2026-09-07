#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# AnnoGrid Stack Setup Script
# Description: Automates the modular deployment of AnnoGrid
# ═══════════════════════════════════════════════════════════════

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting AnnoGrid Modular Setup...${NC}"

# 1. Check for .env file
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found!${NC}"
    echo -e "Please create a .env file based on the template before running this script."
    exit 1
fi

# 2. Create Docker Network if it doesn't exist
NETWORK_NAME="annogrid"
if [ ! "$(docker network ls | grep $NETWORK_NAME)" ]; then
    echo -e "${YELLOW}🌐 Creating shared network: $NETWORK_NAME...${NC}"
    docker network create --subnet=172.20.0.0/24 $NETWORK_NAME
else
    echo -e "${GREEN}✅ Network '$NETWORK_NAME' already exists.${NC}"
fi

# 3. Create necessary volume directories (if using local bind mounts)
# Note: The current docker-compose uses named volumes, but we ensure config dirs exist.
echo -e "${YELLOW}📂 Checking configuration directories...${NC}"
mkdir -p configs/postgres/init-scripts
mkdir -p configs/mariadb
mkdir -p configs/redis
mkdir -p configs/mongodb/init-scripts

# 4. Deploy Stacks
echo -e "${BLUE}🏗️  Deploying Stacks...${NC}"

# Database layer is now external (nodes/anno-db-oci-01/, reached over
# Tailscale) — see docs/guides/db-migration-to-oci.md. docker-compose.db.yml
# is kept as an intentional no-op so this line stays harmless.
echo -e "${YELLOW}📦 Database layer is external (anno-db-oci-01) — skipping local deploy.${NC}"
docker compose -f docker-compose.db.yml up -d

# Start Application Layer
echo -e "${YELLOW}📦 Deploying Application Layer...${NC}"
docker compose -f docker-compose.app.yml up -d

# Start Monitoring Layer
echo -e "${YELLOW}📦 Deploying Monitoring Layer...${NC}"
docker compose -f docker-compose.mon.yml up -d

# 5. Summary
echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}✅ AnnoGrid Setup Complete!${NC}"
echo -e "Use 'docker ps' to verify container status."
echo -e "View the README.md for individual stack management commands."
echo -e "${GREEN}====================================================${NC}"

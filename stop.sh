#!/bin/bash
set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Stop in reverse order
log "Stopping applications..."
docker compose -f collabora/docker-compose.yml down
docker compose -f invoiceplane/docker-compose.yml down
docker compose -f netbox/docker-compose.yml down
docker compose -f zammad/docker-compose.yml down
docker compose -f uptime-kuma/docker-compose.yml down
docker compose -f nextcloud/docker-compose.yml down

log "Stopping shared services..."
docker compose -f shared-services/docker-compose.yml down

log "Stopping Traefik..."
docker compose -f traefik/docker-compose.yml down

log "All services stopped"

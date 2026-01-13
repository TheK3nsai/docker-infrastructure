#!/bin/bash
set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

wait_healthy() {
    local container=$1
    local timeout=${2:-60}
    local elapsed=0

    log "Waiting for $container to be healthy..."
    while [ $elapsed -lt $timeout ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
        if [ "$status" = "healthy" ]; then
            log "$container is healthy"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    warn "$container health check timed out after ${timeout}s"
    return 1
}

# 1. Traefik (reverse proxy)
log "Starting Traefik..."
docker compose -f traefik/docker-compose.yml up -d

# 2. Shared services (databases)
log "Starting shared services..."
docker compose -f shared-services/docker-compose.yml up -d

wait_healthy shared-postgres 90
wait_healthy shared-mariadb 90
wait_healthy shared-redis 60

# 3. Applications (parallel)
log "Starting applications..."
docker compose -f nextcloud/docker-compose.yml up -d
docker compose -f uptime-kuma/docker-compose.yml up -d
docker compose -f zammad/docker-compose.yml up -d
docker compose -f netbox/docker-compose.yml up -d

log "All services started"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20

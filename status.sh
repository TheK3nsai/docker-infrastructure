#!/bin/bash

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Expected containers
CONTAINERS=(
    "traefik"
    "socket-proxy"
    "shared-postgres"
    "shared-mariadb"
    "shared-redis"
    "shared-apache"
    "authentik-server"
    "authentik-worker"
    "prometheus"
    "grafana"
    "node-exporter"
    "cadvisor"
    "nextcloud"
    "nextcloud-cron"
    "zammad-elasticsearch"
    "zammad-memcached"
    "zammad-railsserver"
    "zammad-scheduler"
    "zammad-websocket"
    "netbox"
    "netbox-worker"
    "invoiceplane"
    "collabora"
)

check_container() {
    local name=$1
    local status=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null)
    local health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$name" 2>/dev/null)

    if [ -z "$status" ]; then
        printf "  %-25s ${RED}not found${NC}\n" "$name"
        return 1
    elif [ "$status" != "running" ]; then
        printf "  %-25s ${RED}%s${NC}\n" "$name" "$status"
        return 1
    elif [ "$health" = "unhealthy" ]; then
        printf "  %-25s ${YELLOW}running (unhealthy)${NC}\n" "$name"
        return 1
    elif [ "$health" = "healthy" ]; then
        printf "  %-25s ${GREEN}running (healthy)${NC}\n" "$name"
        return 0
    else
        printf "  %-25s ${GREEN}running${NC}\n" "$name"
        return 0
    fi
}

echo -e "\n${CYAN}=== Container Status ===${NC}\n"

healthy=0
unhealthy=0

for container in "${CONTAINERS[@]}"; do
    if check_container "$container"; then
        ((healthy++))
    else
        ((unhealthy++))
    fi
done

echo -e "\n${CYAN}=== Summary ===${NC}\n"
echo -e "  Healthy:   ${GREEN}$healthy${NC}"
echo -e "  Unhealthy: ${RED}$unhealthy${NC}"
echo -e "  Total:     $((healthy + unhealthy))"

echo -e "\n${CYAN}=== Service URLs ===${NC}\n"
echo "  Traefik:      https://traefik.kensai.cloud"
echo "  Authentik:    https://auth.kensai.cloud"
echo "  Prometheus:   https://prometheus.kensai.cloud"
echo "  Grafana:      https://grafana.kensai.cloud"
echo "  Nextcloud:    https://cloud.kensai.cloud"
echo "  Zammad:       https://tickets.kensai.cloud"
echo "  NetBox:       https://netbox.kensai.cloud"
echo "  InvoicePlane: https://invoices.kensai.cloud"
echo "  Collabora:    https://office.kensai.cloud"

echo -e "\n${CYAN}=== Resource Usage ===${NC}\n"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -20

exit $unhealthy

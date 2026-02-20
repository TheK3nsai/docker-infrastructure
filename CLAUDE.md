# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Docker-based self-hosted infrastructure using Traefik v3 as reverse proxy with Let's Encrypt SSL certificates. All services are on the `kensai.cloud` domain.

## Architecture

### Network Topology
- **traefik-net** (172.19.0.0/24): Public-facing network for services exposed through Traefik
- **shared-db**: Internal network for database/cache connectivity
- **socket-proxy**: Internal network isolating Docker socket access from Traefik

### Service Stack Order (start in this order)
1. **traefik/** - Reverse proxy + socket-proxy (creates traefik-net and socket-proxy networks)
2. **shared-services/** - PostgreSQL, MariaDB, Redis, Authentik, shared-apache (creates shared-db network)
3. **monitoring/** - Prometheus, Grafana, Node Exporter, cAdvisor (creates monitoring network)
4. **Application stacks**: homer/, nextcloud/, zammad/, netbox/, invoiceplane/, collabora/

### Database Assignments
- **PostgreSQL** (shared-postgres): Zammad, Authentik (including cache/sessions), NetBox
- **MariaDB** (shared-mariadb): Nextcloud, InvoicePlane
- **Redis** (shared-redis): DB0=Nextcloud, DB1=(available), DB2=Zammad, DB3=NetBox, DB4=NetBox-cache, DB5=(available)

Note: Authentik 2025.10+ no longer requires Redis - caching, tasks, and WebSockets are handled by PostgreSQL.

### Service Versions (as of February 2026)
| Service | Version | Notes |
|---------|---------|-------|
| Traefik | v3.6.8 | Reverse proxy |
| Socket Proxy | v0.4.2 | Docker socket security |
| PostgreSQL | 18-alpine | Shared database |
| MariaDB | 11.8 | Shared database (LTS) |
| Redis | latest (8.6.0) | Shared cache |
| Authentik | 2025.12.3 | SSO provider (no Redis needed) |
| Nextcloud | latest (32.0.6) | File sync |
| Notify Push | (bundled with Nextcloud) | Client Push via WebSocket (Rust daemon) |
| Zammad | 6.5.2-85 | Ticketing |
| Elasticsearch | 8.19.11 | Zammad search |
| Memcached | latest | Zammad session cache |
| NetBox | v4.5.2 | DCIM/IPAM (2 granian workers) |
| Collabora | latest (25.04.8) | Document editing |
| Apache (httpd) | latest | Shared PHP-FPM proxy |
| Prometheus | latest (3.9.1) | Metrics |
| Grafana | latest (12.3.1) | Dashboards |
| Homer | latest | Dashboard homepage |

### Authentication
Authentik provides SSO via proxy authentication: Services use the `authentik@file` middleware in Traefik (e.g., Traefik Dashboard, NetBox, InvoicePlane, Grafana).

**NetBox API bypass**: The `/api/` path on `netbox.kensai.cloud` has a separate Traefik router (`netbox-api`) that skips Authentik. NetBox handles API authentication natively via token headers (`Authorization: Token <token>`). This allows scripts and automation to use the REST API without SSO interference.

## Common Commands

```bash
# Start infrastructure (run in order)
docker compose -f traefik/docker-compose.yml up -d
docker compose -f shared-services/docker-compose.yml up -d
docker compose -f monitoring/docker-compose.yml up -d
docker compose -f homer/docker-compose.yml up -d
docker compose -f nextcloud/docker-compose.yml up -d
docker compose -f zammad/docker-compose.yml up -d
docker compose -f netbox/docker-compose.yml up -d
docker compose -f invoiceplane/docker-compose.yml up -d
docker compose -f collabora/docker-compose.yml up -d

# View logs
docker logs -f <container-name>

# Restart a single service
docker compose -f <stack>/docker-compose.yml restart <service>

# Check Traefik routing
docker logs traefik 2>&1 | grep -i error
```

## Service URLs
- Homepage: kensai.cloud (Homer dashboard)
- Traefik Dashboard: traefik.kensai.cloud (protected by Authentik)
- Authentik: auth.kensai.cloud
- Prometheus: prometheus.kensai.cloud (protected by Authentik)
- Grafana: grafana.kensai.cloud (protected by Authentik)
- Nextcloud: cloud.kensai.cloud
- Zammad: tickets.kensai.cloud
- NetBox: netbox.kensai.cloud (protected by Authentik)
- InvoicePlane: invoices.kensai.cloud (protected by Authentik)
- Collabora: office.kensai.cloud (document editing for Nextcloud)

## Adding New Services

1. Create `<service>/docker-compose.yml`
2. Connect to `traefik-net` (external: true) for web exposure
3. Connect to `shared-db` (external: true) if using shared databases
4. Add Traefik labels:
   ```yaml
   labels:
     - "traefik.enable=true"
     - "traefik.http.routers.<name>.rule=Host(`<subdomain>.kensai.cloud`)"
     - "traefik.http.routers.<name>.entrypoints=websecure"
     - "traefik.http.routers.<name>.tls.certresolver=letsencrypt"
     - "traefik.http.services.<name>.loadbalancer.server.port=<port>"
     - "traefik.http.routers.<name>.middlewares=security-headers@file"
   ```
5. For Authentik protection, add `authentik@file` to middlewares

## Adding New Databases

- **PostgreSQL**: Add to `shared-services/init-scripts/postgres/init-databases.sql`
- **MariaDB**: Add to `shared-services/init-scripts/mariadb/init-databases.sql`

Note: Init scripts only run on first container creation. For existing installations, run SQL manually.

## Memory Management

All containers have memory limits configured to prevent OOM situations.

### Host System Requirements

**Swap file (4GB minimum):**
```bash
# Create swap file if not exists
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Kernel optimizations** (`/etc/sysctl.d/99-docker-optimization.conf`):
```
vm.swappiness = 30              # Prefer RAM, swap only when necessary (default: 60)
vm.vfs_cache_pressure = 50      # Keep filesystem caches longer for Docker (default: 100)
```

Apply without reboot: `sudo sysctl --system`

### Container Memory Limits

| Stack | Container | Limit | Reservation |
|-------|-----------|-------|-------------|
| traefik | socket-proxy | 128m | 64m |
| traefik | traefik | 256m | 128m |
| shared-services | postgres | 512m | 256m |
| shared-services | mariadb | 256m | 128m |
| shared-services | redis | 128m | 64m |
| shared-services | authentik-server | 1g | 512m |
| shared-services | authentik-worker | 768m | 384m |
| shared-services | apache | 128m | 64m |
| nextcloud | nextcloud | 512m | 256m |
| nextcloud | nextcloud-cron | 256m | 128m |
| nextcloud | notify-push | 128m | 64m |
| zammad | elasticsearch | 1200m | 768m |
| zammad | memcached | 96m | 48m |
| zammad | init | 512m | 256m |
| zammad | railsserver | 768m | 384m |
| zammad | scheduler | 768m | 384m |
| zammad | websocket | 384m | 192m |
| netbox | netbox | 768m | 384m |
| netbox | netbox-worker | 384m | 192m |
| invoiceplane | invoiceplane | 128m | 64m |
| collabora | collabora | 512m | 256m |
| monitoring | prometheus | 1g | 512m |
| monitoring | grafana | 384m | 192m |
| monitoring | node-exporter | 64m | 32m |
| monitoring | cadvisor | 384m | 192m |
| monitoring | postgres-exporter | 128m | 64m |
| monitoring | redis-exporter | 64m | 32m |
| homer | homer | 64m | 32m |

## Shared Apache
The shared-apache container in shared-services proxies requests for PHP-FPM applications:
- **InvoicePlane** (invoices.kensai.cloud) - Serves static files, proxies PHP to invoiceplane:9000

Configuration files are in `shared-services/apache/`:
- `httpd.conf` - Main Apache configuration (based on default with proxy modules enabled)
- `sites-enabled/invoiceplane.conf` - InvoicePlane virtual host

InvoicePlane's PHP-FPM entrypoint handles downloading the code on first run, sharing it with Apache via the `invoiceplane-code` volume.

To add a new app to shared-apache, create a new `.conf` file in `sites-enabled/` and reload: `docker exec shared-apache httpd -k graceful`

## Zammad Architecture

Zammad uses direct Traefik routing (bypassing internal nginx) to avoid CSRF issues with `X-Forwarded-Proto`:
- **Main app**: Traefik → zammad-railsserver:3000
- **WebSockets**: Traefik → zammad-websocket:6042 (path `/ws`)

Required environment settings:
- `ZAMMAD_HTTP_TYPE`: https
- `ZAMMAD_FQDN`: tickets.kensai.cloud
- `RAILS_SERVE_STATIC_FILES`: true (required since nginx is bypassed; Rails serves assets directly)

## Traefik Version Requirements

Traefik requires **v3.6.7+** for proper encoded slash support needed by Collabora WOPI URLs. Versions v3.6.4 through v3.6.6 had a bug breaking URL-encoded character handling (GitHub issue #12437, fixed in PR #12540).

## Collabora Online Integration

Collabora Online provides office document editing (DOCX, ODT, XLSX, PPTX, etc.) for Nextcloud.

### Configuration
The richdocuments app in Nextcloud is configured to use the external Collabora server:
- WOPI URL: `https://office.kensai.cloud`
- Collabora is configured to accept requests only from `cloud.kensai.cloud`
- WOPI allow list in Nextcloud: `127.0.0.1,::1,172.19.0.0/24`

### Container Requirements
Collabora requires special capabilities for optimal performance:
```yaml
cap_add:
  - SYS_ADMIN   # Required for bind mounts in jail namespaces
  - MKNOD
security_opt:
  - seccomp:unconfined  # Allow mount syscalls
tmpfs:
  - /tmp:exec,size=512M  # Fast tmpfs for temp files
```

Without `SYS_ADMIN`, Collabora falls back to slow file copying instead of bind mounts for jail setup.

### Traefik Configuration
Collabora uses multiple middlewares and a custom serversTransport in `traefik/dynamic.yml`:
- `collabora-headers@file`: Security headers with CSP frame-ancestors for Nextcloud embedding
- `collabora-websocket@file`: Adds X-Forwarded-Proto header
- `collabora-transport@file`: Custom timeouts for WebSocket connections (responseHeaderTimeout: 0s)

## Monitoring Stack

The monitoring stack provides infrastructure and container metrics collection and visualization.

### Components
- **Prometheus** (prometheus.kensai.cloud): Time-series metrics database and alerting
- **Grafana** (grafana.kensai.cloud): Metrics visualization and dashboards
- **Node Exporter**: Host system metrics (CPU, memory, disk, network)
- **cAdvisor**: Container metrics (per-container CPU, memory, network, I/O)
- **PostgreSQL Exporter**: Database metrics (connections, transactions, locks, replication)
- **Redis Exporter**: Cache metrics (clients, memory, commands, keys)

### Network Architecture
- Prometheus, Grafana connect to both `traefik-net` (for web access) and `monitoring` network
- Node Exporter and cAdvisor only connect to `monitoring` network (internal only)
- PostgreSQL/Redis Exporters connect to both `monitoring` and `shared-db` networks
- Node Exporter uses `pid: host` for accurate process metrics

### Grafana Authentication
Grafana uses Authentik's forward auth headers for automatic SSO login:
```yaml
# Auth proxy configuration
GF_AUTH_PROXY_ENABLED=true
GF_AUTH_PROXY_HEADER_NAME=X-authentik-username
GF_AUTH_PROXY_HEADER_PROPERTY=username
GF_AUTH_PROXY_AUTO_SIGN_UP=true
GF_AUTH_PROXY_HEADERS=Email:X-authentik-email Name:X-authentik-name
GF_AUTH_PROXY_WHITELIST=172.19.0.0/24
GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN=false

# Disable native login (Authentik handles auth)
GF_AUTH_DISABLE_LOGIN_FORM=true
GF_AUTH_DISABLE_SIGNOUT_MENU=true
```

Users authenticated through Authentik are automatically logged into Grafana without seeing a login page.

### Pre-installed Dashboards
- **Node Exporter Full** (ID 1860): Comprehensive host system metrics
- **Docker/cAdvisor** (ID 14282): Container resource usage metrics

### Prometheus Scrape Targets
Configured in `monitoring/prometheus.yml`:
- `prometheus` (localhost:9090): Prometheus self-monitoring
- `node-exporter` (node-exporter:9100): Host metrics
- `cadvisor` (cadvisor:8080): Container metrics
- `traefik` (traefik:8082): Traefik reverse proxy metrics
- `postgres-exporter` (postgres-exporter:9187): PostgreSQL database metrics
- `redis-exporter` (redis-exporter:9121): Redis cache metrics

### Configuration Files
- `monitoring/docker-compose.yml` - All monitoring services
- `monitoring/prometheus.yml` - Prometheus scrape configuration
- `monitoring/grafana/provisioning/datasources/` - Auto-provisioned datasources
- `monitoring/grafana/provisioning/dashboards/` - Dashboard provisioning config
- `monitoring/grafana/dashboards/` - Dashboard JSON files
- `monitoring/.env` - Grafana admin password and SMTP credentials

### Email Alerts (Gmail SMTP)
Grafana is configured to send email alerts via Gmail SMTP. Configuration is set via environment variables in `monitoring/.env`:
```
GF_SMTP_USER=your-email@gmail.com
GF_SMTP_PASSWORD=your-16-char-app-password
GF_SMTP_FROM_ADDRESS=your-email@gmail.com
```

**Setup requirements:**
1. Enable 2FA on your Google account
2. Generate an App Password at https://myaccount.google.com/apppasswords
3. Use the 16-character App Password (not your regular Gmail password)

**Note:** After modifying SMTP settings in `.env`, you must recreate the container (not just restart):
```bash
docker compose -f monitoring/docker-compose.yml up -d grafana
```

Configure alert recipients in Grafana under **Alerting → Contact points**.

### Alert Rules (File Provisioned)
Alert rules are provisioned via file at `monitoring/grafana/provisioning/alerting/`. Edit the YAML file and restart Grafana to update rules. UI-based edits will not persist across container restarts.

**Configured alerts** (folder: Infrastructure, evaluation interval: 1m):

| Alert | Condition | Duration | Severity | Notes |
|-------|-----------|----------|----------|-------|
| High Memory Usage | Memory usage > 85% | 5m | critical | |
| Disk Space Low | Root filesystem usage > 85% | 5m | warning | |
| High Load Average | 15-min load average > 4 | 10m | warning | |
| Critical Container Down | Any of: traefik, shared-postgres, shared-mariadb, shared-redis, authentik-server missing | 1m | critical | |
| High HTTP Error Rate | 5xx errors > 5% of requests | 5m | warning | noDataState: OK (no 5xx = healthy) |
| Traefik Down | Traefik metrics endpoint unreachable | 1m | critical | |

All alerts send notifications to the "Email" contact point.

**Modifying alerts:**
```bash
# Edit the alert rules file
vim monitoring/grafana/provisioning/alerting/alert-rules-*.yaml

# Restart Grafana to apply changes
docker compose -f monitoring/docker-compose.yml restart grafana
```

## Helper Scripts

- `./start.sh` - Start all services in correct order with health checks
- `./stop.sh` - Stop all services in reverse order
- `./status.sh` - Show container status, health, and resource usage

## Configuration Files

- `traefik/traefik.yml` - Static config (entrypoints, providers, TLS settings)
- `traefik/dynamic.yml` - Dynamic config (middlewares, watched for changes)
- `traefik/acme.json` - Let's Encrypt certificates (auto-managed)
- `shared-services/apache/` - Shared apache configuration
- `shared-services/init-scripts/` - Database initialization SQL scripts
- `monitoring/prometheus.yml` - Prometheus scrape configuration
- `monitoring/grafana/provisioning/` - Grafana auto-provisioning configs
- `monitoring/grafana/provisioning/alerting/` - File-provisioned alert rules
- `monitoring/grafana/dashboards/` - Pre-installed Grafana dashboards
- `netbox/extra.py` - NetBox extra config (API_TOKEN_PEPPERS for v2 API tokens)
- `homer/config/config.yml` - Homer dashboard configuration
- `.env` files in each stack directory contain secrets

## Troubleshooting

### Zammad CSRF Token Errors
Zammad requires `http_type=https` and `fqdn=tickets.kensai.cloud` in the database. These are set via environment variables `ZAMMAD_HTTP_TYPE` and `ZAMMAD_FQDN`. Direct Traefik routing bypasses internal nginx to avoid header issues.

### InvoicePlane Setup Loop
InvoicePlane checks `SETUP_COMPLETED=true` in `ipconfig.php` (not in database). Ensure this is set after completing setup wizard.

### Nextcloud Notify Push (Client Push)
The `notify-push` container is a lightweight Rust daemon that replaces client polling with WebSocket push notifications. Clients connect once via WebSocket and receive instant change notifications via Redis pub/sub, eliminating the 30-second polling cycle.

**Setup (one-time, after first deploy):**
```bash
docker exec -u www-data nextcloud php occ app:install notify_push
docker compose -f nextcloud/docker-compose.yml up -d notify-push
docker exec -u www-data nextcloud php occ notify_push:setup https://cloud.kensai.cloud/push
```

**Traefik routing**: The `/push` path on `cloud.kensai.cloud` routes to `nextcloud-notify-push:7867` with a `stripprefix` middleware removing `/push` before forwarding.

**Verify**: `docker exec -u www-data nextcloud php occ notify_push:self-test`

### NetBox API Token Peppers
NetBox v4.5+ requires `API_TOKEN_PEPPERS` to create v2 API tokens. This is configured in `netbox/extra.py` (bind-mounted into both `netbox` and `netbox-worker` containers at `/etc/netbox/config/extra.py`). Keys must be integers, not strings: `{2: 'hex-string'}`.

### NetBox High Memory Usage
NetBox uses granian (WSGI server) which defaults to 4 workers (`nproc`). Each worker consumes ~150-220MB. Set `GRANIAN_WORKERS: 2` in the environment to reduce memory usage for single-user deployments. The launch script reads `${GRANIAN_WORKERS:-4}`.

### Container Health Issues
```bash
# Check specific container logs
docker logs <container-name> --tail 100

# Check all container status
./status.sh

# Restart a specific stack
docker compose -f <stack>/docker-compose.yml restart
```

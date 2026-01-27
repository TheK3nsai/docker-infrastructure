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
2. **shared-services/** - PostgreSQL, MariaDB, Redis, Authentik, shared-nginx, shared-apache (creates shared-db network)
3. **monitoring/** - Prometheus, Grafana, Node Exporter, cAdvisor (creates monitoring network)
4. **Application stacks**: nextcloud/, uptime-kuma/, zammad/, netbox/, invoiceplane/, collabora/, forgejo/

### Database Assignments
- **PostgreSQL** (shared-postgres): Zammad, Authentik, NetBox, Forgejo
- **MariaDB** (shared-mariadb): Nextcloud, InvoicePlane
- **Redis** (shared-redis): DB0=Nextcloud, DB1=Authentik, DB2=Zammad, DB3=NetBox, DB4=NetBox-cache, DB5=Forgejo

### Authentication
Authentik provides SSO via two methods:
- **Proxy authentication**: Services use the `authentik@file` middleware in Traefik (e.g., Traefik Dashboard, Uptime Kuma, NetBox, InvoicePlane)
- **OAuth2/OIDC**: Services use native OAuth2 login with Authentik as identity provider (e.g., Forgejo)

## Common Commands

```bash
# Start infrastructure (run in order)
docker compose -f traefik/docker-compose.yml up -d
docker compose -f shared-services/docker-compose.yml up -d
docker compose -f monitoring/docker-compose.yml up -d
docker compose -f nextcloud/docker-compose.yml up -d
docker compose -f uptime-kuma/docker-compose.yml up -d
docker compose -f zammad/docker-compose.yml up -d
docker compose -f netbox/docker-compose.yml up -d
docker compose -f invoiceplane/docker-compose.yml up -d
docker compose -f collabora/docker-compose.yml up -d
docker compose -f forgejo/docker-compose.yml up -d

# View logs
docker logs -f <container-name>

# Restart a single service
docker compose -f <stack>/docker-compose.yml restart <service>

# Check Traefik routing
docker logs traefik 2>&1 | grep -i error
```

## Service URLs
- Traefik Dashboard: traefik.kensai.cloud (protected by Authentik)
- Authentik: auth.kensai.cloud
- Prometheus: prometheus.kensai.cloud (protected by Authentik)
- Grafana: grafana.kensai.cloud (protected by Authentik)
- Nextcloud: cloud.kensai.cloud
- Uptime Kuma: uptime.kensai.cloud (protected by Authentik)
- Zammad: tickets.kensai.cloud
- NetBox: netbox.kensai.cloud (protected by Authentik)
- InvoicePlane: invoices.kensai.cloud (protected by Authentik)
- Collabora: office.kensai.cloud (document editing for Nextcloud)
- Forgejo: git.kensai.cloud (OAuth2 via Authentik, SSH on port 2222)

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

All containers have memory limits configured to prevent OOM situations. The host requires a 4GB swap file for safety.

| Stack | Container | Limit | Reservation |
|-------|-----------|-------|-------------|
| traefik | socket-proxy | 256m | 128m |
| traefik | traefik | 512m | 256m |
| shared-services | postgres | 512m | 256m |
| shared-services | mariadb | 512m | 256m |
| shared-services | redis | 256m | 128m |
| shared-services | authentik-server | 1g | 512m |
| shared-services | authentik-worker | 768m | 384m |
| shared-services | nginx | 256m | 128m |
| shared-services | apache | 256m | 128m |
| nextcloud | nextcloud | 1g | 512m |
| nextcloud | nextcloud-cron | 256m | 128m |
| uptime-kuma | uptime-kuma | 512m | 256m |
| zammad | elasticsearch | 1200m | 768m |
| zammad | memcached | 128m | 96m |
| zammad | railsserver | 512m | 256m |
| zammad | scheduler | 512m | 256m |
| zammad | websocket | 512m | 256m |
| netbox | netbox | 768m | 384m |
| netbox | netbox-worker | 512m | 256m |
| invoiceplane | invoiceplane | 384m | 192m |
| collabora | collabora | 1536m | 1g |
| forgejo | forgejo | 512m | 256m |
| monitoring | prometheus | 512m | 256m |
| monitoring | grafana | 512m | 256m |
| monitoring | node-exporter | 128m | 64m |
| monitoring | cadvisor | 256m | 128m |

## Shared Web Servers

### Shared Nginx
The shared-nginx container in shared-services is available for future Rails/static applications.

Configuration files are in `shared-services/nginx/`:
- `nginx.conf` - Main nginx configuration
- `conf.d/` - Virtual host configurations

To add a new app to shared-nginx, create a new `.conf` file in `conf.d/` and reload: `docker exec shared-nginx nginx -s reload`

### Shared Apache
The shared-apache container in shared-services proxies requests for PHP-FPM applications:
- **InvoicePlane** (invoices.kensai.cloud) - Serves static files, proxies PHP to invoiceplane:9000

Configuration files are in `shared-services/apache/`:
- `httpd.conf` - Main Apache configuration (based on default with proxy modules enabled)
- `sites-enabled/invoiceplane.conf` - InvoicePlane virtual host

InvoicePlane uses an init container pattern to download code and share it between PHP-FPM and Apache via the `invoiceplane-code` volume.

To add a new app to shared-apache, create a new `.conf` file in `sites-enabled/` and reload: `docker exec shared-apache httpd -k graceful`

## Zammad Architecture

Zammad uses direct Traefik routing (bypassing internal nginx) to avoid CSRF issues with `X-Forwarded-Proto`:
- **Main app**: Traefik → zammad-railsserver:3000
- **WebSockets**: Traefik → zammad-websocket:6042 (path `/ws`)

Required database settings (set automatically):
- `http_type`: https
- `fqdn`: tickets.kensai.cloud

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

## Forgejo OAuth2 Integration

Forgejo uses native OAuth2/OpenID Connect authentication with Authentik (not proxy authentication).

### Authentication Flow
Users access Forgejo directly and click "Sign in with Authentik" on the login page. This uses Forgejo's built-in OAuth2 client to authenticate against Authentik.

### Configuration
OAuth2 is configured via:
1. **Environment variables** in `forgejo/docker-compose.yml`:
   ```yaml
   - FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION=true
   - FORGEJO__oauth2_client__USERNAME=nickname
   - FORGEJO__oauth2_client__ACCOUNT_LINKING=auto
   - FORGEJO__service__ALLOW_ONLY_EXTERNAL_REGISTRATION=true
   ```

2. **OAuth2 authentication source** stored in database (added via CLI):
   ```bash
   docker exec -u git forgejo forgejo --config /data/gitea/conf/app.ini admin auth add-oauth \
     --name "Authentik" \
     --provider openidConnect \
     --key "<client_id>" \
     --secret "<client_secret>" \
     --auto-discover-url "https://auth.kensai.cloud/application/o/forgejo/.well-known/openid-configuration"
   ```

### Authentik Requirements
In Authentik, configure an **OAuth2/OpenID Provider** (not Proxy Provider) with:
- **Client ID/Secret**: As configured in Forgejo
- **Redirect URI**: `https://git.kensai.cloud/user/oauth2/Authentik/callback`
- **Scopes**: openid, email, profile

### Key Differences from Proxy Auth
- No `authentik@file` middleware in Traefik labels (users access Forgejo directly)
- Authentication happens through Forgejo's login page, not Authentik's proxy
- Users can still access public repositories without authentication

## Monitoring Stack

The monitoring stack provides infrastructure and container metrics collection and visualization.

### Components
- **Prometheus** (prometheus.kensai.cloud): Time-series metrics database and alerting
- **Grafana** (grafana.kensai.cloud): Metrics visualization and dashboards
- **Node Exporter**: Host system metrics (CPU, memory, disk, network)
- **cAdvisor**: Container metrics (per-container CPU, memory, network, I/O)

### Network Architecture
- Prometheus, Grafana connect to both `traefik-net` (for web access) and `monitoring` network
- Node Exporter and cAdvisor only connect to `monitoring` network (internal only)
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

### Configuration Files
- `monitoring/docker-compose.yml` - All monitoring services
- `monitoring/prometheus.yml` - Prometheus scrape configuration
- `monitoring/grafana/provisioning/datasources/` - Auto-provisioned datasources
- `monitoring/grafana/provisioning/dashboards/` - Dashboard provisioning config
- `monitoring/grafana/dashboards/` - Dashboard JSON files
- `monitoring/.env` - Grafana admin password

## Helper Scripts

- `./start.sh` - Start all services in correct order with health checks
- `./stop.sh` - Stop all services in reverse order
- `./status.sh` - Show container status, health, and resource usage

## Configuration Files

- `traefik/traefik.yml` - Static config (entrypoints, providers, TLS settings)
- `traefik/dynamic.yml` - Dynamic config (middlewares, watched for changes)
- `traefik/acme.json` - Let's Encrypt certificates (auto-managed)
- `shared-services/nginx/` - Shared nginx configuration
- `shared-services/apache/` - Shared apache configuration
- `shared-services/init-scripts/` - Database initialization SQL scripts
- `monitoring/prometheus.yml` - Prometheus scrape configuration
- `monitoring/grafana/provisioning/` - Grafana auto-provisioning configs
- `monitoring/grafana/dashboards/` - Pre-installed Grafana dashboards
- `.env` files in each stack directory contain secrets

## Troubleshooting

### Zammad CSRF Token Errors
Zammad requires `http_type=https` and `fqdn=tickets.kensai.cloud` in the database. These are set via environment variables `ZAMMAD_HTTP_TYPE` and `ZAMMAD_FQDN`. Direct Traefik routing bypasses internal nginx to avoid header issues.

### InvoicePlane Setup Loop
InvoicePlane checks `SETUP_COMPLETED=true` in `ipconfig.php` (not in database). Ensure this is set after completing setup wizard.

### Container Health Issues
```bash
# Check specific container logs
docker logs <container-name> --tail 100

# Check all container status
./status.sh

# Restart a specific stack
docker compose -f <stack>/docker-compose.yml restart
```

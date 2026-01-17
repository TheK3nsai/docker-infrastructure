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
3. **Application stacks**: nextcloud/, uptime-kuma/, zammad/, netbox/, invoiceplane/

### Database Assignments
- **PostgreSQL** (shared-postgres): Zammad, Authentik, NetBox
- **MariaDB** (shared-mariadb): Nextcloud, InvoicePlane
- **Redis** (shared-redis): DB0=Nextcloud, DB1=Authentik, DB2=Zammad, DB3=NetBox, DB4=NetBox-cache

### Authentication
Authentik provides SSO. Services protected by Authentik use the `authentik@file` middleware defined in `traefik/dynamic.yml`.

## Common Commands

```bash
# Start infrastructure (run in order)
docker compose -f traefik/docker-compose.yml up -d
docker compose -f shared-services/docker-compose.yml up -d
docker compose -f nextcloud/docker-compose.yml up -d
docker compose -f uptime-kuma/docker-compose.yml up -d
docker compose -f zammad/docker-compose.yml up -d
docker compose -f netbox/docker-compose.yml up -d
docker compose -f invoiceplane/docker-compose.yml up -d

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
- Nextcloud: cloud.kensai.cloud
- Uptime Kuma: uptime.kensai.cloud (protected by Authentik)
- Zammad: tickets.kensai.cloud
- NetBox: netbox.kensai.cloud
- InvoicePlane: invoices.kensai.cloud (protected by Authentik)

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

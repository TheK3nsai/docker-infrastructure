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
2. **shared-services/** - PostgreSQL, MariaDB, Redis, Authentik (creates shared-db network)
3. **Application stacks**: nextcloud/, uptime-kuma/, zammad/, netbox/

### Database Assignments
- **PostgreSQL** (shared-postgres): Zammad, Authentik, NetBox
- **MariaDB** (shared-mariadb): Nextcloud
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

## Configuration Files

- `traefik/traefik.yml` - Static config (entrypoints, providers, TLS settings)
- `traefik/dynamic.yml` - Dynamic config (middlewares, watched for changes)
- `traefik/acme.json` - Let's Encrypt certificates (auto-managed)
- `.env` files in each stack directory contain secrets

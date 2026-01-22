# Docker Infrastructure

Self-hosted Docker infrastructure with Traefik reverse proxy, shared databases, and SSO via Authentik.

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Traefik | traefik.kensai.cloud | Reverse proxy dashboard |
| Authentik | auth.kensai.cloud | Identity provider / SSO |
| Nextcloud | cloud.kensai.cloud | File sync and collaboration |
| Collabora | office.kensai.cloud | Online office suite for Nextcloud |
| Uptime Kuma | uptime.kensai.cloud | Monitoring dashboard |
| Zammad | tickets.kensai.cloud | Helpdesk / ticketing system |
| NetBox | netbox.kensai.cloud | IPAM / DCIM infrastructure management |
| InvoicePlane | invoices.kensai.cloud | Open source invoicing |

## Architecture

```
                              ┌─────────────────────────────────────────┐
                              │              Internet                    │
                              └───────────────────┬─────────────────────┘
                                                  │ :80/:443
                              ┌───────────────────▼─────────────────────┐
                              │              Traefik                     │
                              │         (reverse proxy)                  │
                              └───────────────────┬─────────────────────┘
                                                  │ traefik-net
      ┌──────────────┬───────────────┬────────────┴────────┬───────────────┬──────────────┬──────────────┬──────────────┐
      ▼              ▼               ▼                     ▼               ▼              ▼              ▼              ▼
┌──────────┐  ┌──────────┐   ┌──────────┐          ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Authentik│  │ Nextcloud│   │ Collabora│          │  Zammad  │   │  Uptime  │   │  NetBox  │   │ Invoice  │   │  Future  │
│   SSO    │  │          │   │  Online  │          │          │   │   Kuma   │   │IPAM/DCIM │   │  Plane   │   │  Apps    │
└────┬─────┘  └────┬─────┘   └──────────┘          └────┬─────┘   └──────────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘
     │             │                                    │                              │              │              │
     └─────────────┴────────────────────────────────────┴──────────────────────────────┴──────────────┴──────────────┘
                                  │ shared-db
                    ┌─────────────┴───────────────────────────┐
                    │           Shared Services                │
                    │  PostgreSQL │ MariaDB │ Redis │ Apache   │
                    └──────────────────────────────────────────┘
```

## Prerequisites

- Docker and Docker Compose v2
- Domain with DNS pointing to your server
- Ports 80 and 443 available

## Helper Scripts

```bash
./start.sh   # Start all services in correct order with health checks
./stop.sh    # Stop all services in reverse order
./status.sh  # Show container status, health, and resource usage
```

## Quick Start

### 1. Clone and configure environment files

```bash
# Copy example env files and edit with your values
cp shared-services/.env.example shared-services/.env
cp nextcloud/.env.example nextcloud/.env
cp zammad/.env.example zammad/.env
cp netbox/.env.example netbox/.env
cp invoiceplane/.env.example invoiceplane/.env
cp collabora/.env.example collabora/.env
```

### 2. Set up Traefik certificates file

```bash
touch traefik/acme.json
chmod 600 traefik/acme.json
```

### 3. Start services in order

```bash
# 1. Start Traefik (creates traefik-net network)
docker compose -f traefik/docker-compose.yml up -d

# 2. Start shared services (creates shared-db network)
docker compose -f shared-services/docker-compose.yml up -d

# 3. Wait for databases to be healthy
docker compose -f shared-services/docker-compose.yml ps

# 4. Start applications
docker compose -f nextcloud/docker-compose.yml up -d
docker compose -f uptime-kuma/docker-compose.yml up -d
docker compose -f zammad/docker-compose.yml up -d
docker compose -f netbox/docker-compose.yml up -d
docker compose -f invoiceplane/docker-compose.yml up -d
docker compose -f collabora/docker-compose.yml up -d
```

### 4. Initial Authentik setup

1. Navigate to https://auth.kensai.cloud/if/flow/initial-setup/
2. Create admin account
3. Configure outpost for Traefik forward auth

## Directory Structure

```
docker/
├── traefik/                 # Reverse proxy
│   ├── docker-compose.yml
│   ├── traefik.yml          # Static configuration
│   ├── dynamic.yml          # Dynamic configuration (middlewares)
│   └── acme.json            # Let's Encrypt certificates
├── shared-services/         # Databases, Authentik, shared nginx & apache
│   ├── docker-compose.yml
│   ├── .env
│   ├── init-scripts/        # Database initialization
│   │   ├── postgres/
│   │   └── mariadb/
│   ├── nginx/               # Shared nginx configuration
│   │   ├── nginx.conf
│   │   └── conf.d/          # Virtual host configurations
│   └── apache/              # Shared apache configuration
│       ├── httpd.conf
│       └── sites-enabled/   # Virtual hosts (invoiceplane.conf)
├── nextcloud/
│   ├── docker-compose.yml
│   └── .env
├── uptime-kuma/
│   └── docker-compose.yml
├── zammad/
│   ├── docker-compose.yml
│   └── .env
├── netbox/
│   ├── docker-compose.yml
│   └── .env
├── invoiceplane/
│   ├── docker-compose.yml
│   ├── Dockerfile           # Custom PHP-FPM with required extensions
│   └── .env
└── collabora/
    ├── docker-compose.yml
    └── .env
```

## Networks

| Network | Purpose |
|---------|---------|
| traefik-net | Services exposed to internet via Traefik |
| shared-db | Internal database connectivity |
| socket-proxy | Isolated Docker socket access |

## Database Allocation

| Database | Engine | Used By |
|----------|--------|---------|
| authentik | PostgreSQL | Authentik |
| zammad | PostgreSQL | Zammad |
| netbox | PostgreSQL | NetBox |
| nextcloud | MariaDB | Nextcloud |
| invoiceplane | MariaDB | InvoicePlane |

Redis databases: 0=Nextcloud, 1=Authentik, 2=Zammad, 3=NetBox, 4=NetBox-cache

## Common Operations

### View logs
```bash
docker logs -f traefik
docker logs -f authentik-server
docker logs -f nextcloud
docker logs -f collabora
docker logs -f netbox
docker logs -f invoiceplane
```

### Restart a stack
```bash
docker compose -f <stack>/docker-compose.yml restart
```

### Update images
```bash
docker compose -f <stack>/docker-compose.yml pull
docker compose -f <stack>/docker-compose.yml up -d
```

### Backup databases
```bash
# PostgreSQL
docker exec shared-postgres pg_dumpall -U postgres > backup.sql

# MariaDB
docker exec shared-mariadb mysqldump -u root -p --all-databases > backup.sql
```

## Adding a New Service

1. Create a new directory with `docker-compose.yml`
2. Connect to required networks:
   ```yaml
   networks:
     traefik-net:
       external: true
     shared-db:        # if using shared databases
       external: true
   ```
3. Add Traefik labels for routing:
   ```yaml
   labels:
     - "traefik.enable=true"
     - "traefik.http.routers.myapp.rule=Host(`myapp.kensai.cloud`)"
     - "traefik.http.routers.myapp.entrypoints=websecure"
     - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
     - "traefik.http.services.myapp.loadbalancer.server.port=8080"
     - "traefik.http.routers.myapp.middlewares=security-headers@file"
   ```
4. For SSO protection, add `authentik@file` to middlewares

## Troubleshooting

### Traefik not routing to service
- Verify container is on `traefik-net`: `docker network inspect traefik-net`
- Check Traefik logs: `docker logs traefik 2>&1 | grep <service>`
- Ensure `traefik.enable=true` label is set

### Database connection refused
- Verify shared-services stack is running: `docker compose -f shared-services/docker-compose.yml ps`
- Check container is on `shared-db` network
- Verify credentials in `.env` file

### Certificate errors
- Check `acme.json` permissions: `chmod 600 traefik/acme.json`
- Verify DNS is pointing to server
- Check Traefik logs for ACME errors

### Zammad CSRF token errors
Zammad uses direct Traefik routing to railsserver:3000 (bypassing internal nginx) to avoid `X-Forwarded-Proto` header issues. Environment variables `ZAMMAD_HTTP_TYPE=https` and `ZAMMAD_FQDN` must be set.

### InvoicePlane keeps showing setup
InvoicePlane checks `SETUP_COMPLETED=true` in `ipconfig.php` (stored in Docker volume). Ensure this is set after completing the setup wizard.

### Collabora documents not loading
Collabora requires Traefik v3.6.7+ for encoded slash support in WOPI URLs. The container also needs `SYS_ADMIN` capability for optimal performance. Verify the Nextcloud richdocuments app is configured with WOPI URL `https://office.kensai.cloud`.

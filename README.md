# jm-n8n

Custom n8n Docker image with security and database tools. Automatically built and published to GHCR when new n8n versions are released.

## Features

- **PostgreSQL client** (18 tools): psql, pg_dump, pg_restore, etc.
- **ProjectDiscovery tools** (25 tools): nuclei, httpx, subfinder, katana, dnsx, etc.
- **Network tools**: nmap, massdns
- Multi-platform support (linux/amd64, linux/arm64)
- Queue mode ready with Redis support
- Auto-updated daily via GitHub Actions

## Quick Start

```bash
# Pull the image
docker pull ghcr.io/justmumu/jm-n8n:latest

# Or use docker-compose
cd n8n-hosting/postgresql-redis-n8n
docker compose -f docker-compose-n8n-main.yml up -d
```

### Running a Worker

```bash
docker compose -f docker-compose-n8n-worker.yml up -d
```

## Project Structure

```
├── Dockerfile                          # Custom n8n image with tools
├── .github/workflows/auto-build.yml    # Daily auto-build workflow
└── n8n-hosting/postgresql-redis-n8n/
    ├── docker-compose-n8n-main.yml     # Main instance (PostgreSQL + Redis + n8n)
    ├── docker-compose-n8n-worker.yml   # Worker instance
    └── init-data.sh                    # PostgreSQL init script
```

## Environment Variables

Create a `.env` file with the following variables:

```env
# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
POSTGRES_DB=n8n
POSTGRES_NON_ROOT_USER=n8n_user
POSTGRES_NON_ROOT_PASSWORD=n8n_password

# Redis
REDIS_PASSWORD=redis_password

# n8n
N8N_ENCRYPTION_KEY=your_encryption_key
WEBHOOK_URL=https://your-domain.com
GENERIC_TIMEZONE=Europe/Istanbul

# Optional
N8N_METRICS=true
N8N_METRICS_INCLUDE_QUEUE_METRICS=true
N8N_PROXY_HOPS=1
```

## License

[MIT](LICENSE)

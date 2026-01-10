# jm-n8n

Custom n8n Docker image with security and database tools. Automatically built and published to GHCR when new n8n versions are released.

## Features

- **PostgreSQL client** (18 tools): psql, pg_dump, pg_restore, etc.
- **ProjectDiscovery tools** (25 tools): nuclei, httpx, subfinder, katana, dnsx, etc.
- **Network tools**: nmap, massdns
- Multi-platform support (linux/amd64, linux/arm64)
- Queue mode ready with Redis support
- Google Drive backup with retention policy
- Auto-updated daily via GitHub Actions

## Quick Start

```bash
# Pull the image
docker pull ghcr.io/justmumu/jm-n8n:latest
```

### Using Docker Compose (Recommended)

```bash
cd n8n-hosting/postgresql-redis-n8n

# Main server (PostgreSQL + Redis + n8n)
COMPOSE_PROFILES=main docker compose up -d

# Worker server (on separate machine)
COMPOSE_PROFILES=worker docker compose up -d

# Run backup manually
docker compose --profile backup run --rm backup
```

## Backup

Automated backup to Google Team Drive with 30-day retention.

### Setup

1. Create a Google Cloud service account with Drive API access
2. Share your Team Drive folder with the service account email
3. Copy `backup/service-account.json.example` to `backup/service-account.json`
4. Add your service account credentials

### Cronjob (every 12 hours)

```bash
0 */12 * * * cd /path/to/n8n-hosting/postgresql-redis-n8n && docker compose --profile backup run --rm backup
```

## Project Structure

```
├── Dockerfile                          # Custom n8n image with tools
├── .github/workflows/auto-build.yml    # Daily auto-build workflow
└── n8n-hosting/postgresql-redis-n8n/
    ├── docker-compose.yml              # Unified compose with profiles
    ├── docker-compose-n8n-main.yml     # Main instance (legacy)
    ├── docker-compose-n8n-worker.yml   # Worker instance (legacy)
    ├── init-data.sh                    # PostgreSQL init script
    └── backup/
        ├── Dockerfile                  # Backup container
        ├── backup.sh                   # Backup script
        └── service-account.json.example
```

## Environment Variables

Create a `.env` file:

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

# Backup - Google Team Drive (optional)
GDRIVE_SERVICE_ACCOUNT_PATH=./backup/service-account.json
GDRIVE_TEAM_DRIVE_ID=your-team-drive-id
GDRIVE_ROOT_FOLDER_ID=your-folder-id-in-team-drive

# Backup notifications (optional)
BACKUP_SVC_NOTIFICATION_URL=https://your-webhook-url
BACKUP_SVC_API_HEADER=X-Api-Key
BACKUP_SVC_API_KEY=your-api-key
```

## License

[MIT](LICENSE)

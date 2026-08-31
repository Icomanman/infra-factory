# Docker Setup for the Production VPS

This guide sets up the target application architecture on the VPS:

```text
Internet
    |
engine.miyeoh.com
    |
    v
Caddy (HTTPS)
    |
    v
Backend container
    |
    v
PostgreSQL container
    |
    v
Azure Blob Storage (database backups)
```

The VPS and Docker installation are already complete. This guide does not
cover SSH setup, VPS provisioning, Terraform, or Docker fundamentals.

## 1. Prerequisites

The following must already be true:

- Docker and the Docker Compose plugin are installed;
- the VPS firewall allows TCP ports `80` and `443`;
- `engine.miyeoh.com` has a DNS `A` record pointing to the VPS public IP;
- the GitHub repository containing the backend is available to the VPS; and
- the backend listens on port `3000` inside its container.

The backend repository must contain a working `Dockerfile`. If it listens on a
different port, change `BACKEND_PORT` and the Compose configuration below.

Verify Docker:

```bash
docker version
docker compose version
```

## 2. Create the deployment directory

Run the following as the normal VPS user:

```bash
sudo mkdir -p /opt/engine
sudo chown -R "$USER":"$USER" /opt/engine
cd /opt/engine
```

Clone the backend repository into the deployment directory:

```bash
git clone https://github.com/OWNER/BACKEND_REPOSITORY.git backend
```

Replace the repository URL with the real GitHub repository. The resulting
layout is:

```text
/opt/engine/
├── backend/
├── compose.yml
├── Caddyfile
├── .env
└── scripts/
    └── backup.sh
```

## 3. Create the production environment file

Create `/opt/engine/.env`:

```dotenv
DOMAIN=engine.miyeoh.com
BACKEND_PORT=3000

POSTGRES_DB=engine
POSTGRES_USER=engine
POSTGRES_PASSWORD=replace-with-a-long-random-password

DATABASE_URL=postgresql://engine:replace-with-a-long-random-password@postgres:5432/engine

# Azure Blob Storage destination for the backup script.
AZURE_BLOB_CONTAINER_URL=https://STORAGE_ACCOUNT.blob.core.windows.net/CONTAINER
AZURE_BLOB_SAS_TOKEN=?SAS_TOKEN
```

Generate a database password:

```bash
openssl rand -hex 32
```

Use the generated value in both `POSTGRES_PASSWORD` and `DATABASE_URL`.
Replace the Azure Blob values with a container URL and container-scoped SAS
token that has permission to create blobs.

Protect the file:

```bash
chmod 600 /opt/engine/.env
```

Do not commit `.env` to Git.

## 4. Define the Docker services

Create `/opt/engine/compose.yml`:

```yaml
services:
  postgres:
    image: postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - private

  backend:
    build:
      context: ./backend
    restart: unless-stopped
    environment:
      DATABASE_URL: ${DATABASE_URL}
      PORT: ${BACKEND_PORT}
    expose:
      - "${BACKEND_PORT}"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - private
      - public

  caddy:
    image: caddy:2
    restart: unless-stopped
    environment:
      DOMAIN: ${DOMAIN}
      BACKEND_PORT: ${BACKEND_PORT}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - backend
    networks:
      - public

volumes:
  postgres_data:
  caddy_data:
  caddy_config:

networks:
  private:
    internal: true
  public:
```

The network boundaries are important:

- Caddy is the only container exposing host ports;
- the backend is available to Caddy but not directly to the Internet;
- PostgreSQL is available only to the backend;
- PostgreSQL data is stored in a named Docker volume; and
- Caddy's certificate data is stored in a named Docker volume.

## 5. Configure Caddy

Create `/opt/engine/Caddyfile`:

```caddyfile
{$DOMAIN} {
    reverse_proxy backend:{$BACKEND_PORT}
}
```

Caddy will request and renew the TLS certificate automatically. The DNS record
and inbound ports `80` and `443` must be working before starting Caddy.

## 6. Build and start the stack

Validate the expanded Compose configuration first:

```bash
cd /opt/engine
docker compose config
```

Start the database and backend:

```bash
docker compose up -d --build postgres backend
docker compose ps
```

Run the backend's migration command, if the project requires one. For example,
the actual command might be one of these, depending on the framework:

```bash
docker compose exec backend npm run migrate
docker compose exec backend python manage.py migrate
```

Do not run an example command unless it is the command defined by the backend
project.

Start Caddy:

```bash
docker compose up -d caddy
docker compose ps
```

Check the services:

```bash
docker compose logs --tail=100 postgres
docker compose logs --tail=100 backend
docker compose logs --tail=100 caddy
curl --fail-with-body https://engine.miyeoh.com/
```

## 7. Deploy backend changes

Pull the latest source and rebuild only the backend:

```bash
cd /opt/engine/backend
git pull --ff-only

cd /opt/engine
docker compose up -d --build backend
docker compose ps
```

Run database migrations after deploying a version that changes the schema.

Do not use `docker compose down -v`: removing volumes can delete the
PostgreSQL database.

## 8. Back up PostgreSQL to Azure Blob Storage

Install `azcopy` on the VPS using Microsoft's current installation
instructions, then verify it is available:

```bash
azcopy --version
```

Create `/opt/engine/scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd /opt/engine
set -a
. ./.env
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="/tmp/engine-${timestamp}.sql.gz"

cleanup() {
  rm -f "$backup_file"
}
trap cleanup EXIT

docker compose exec -T postgres \
  pg_dump \
  --username="$POSTGRES_USER" \
  --dbname="$POSTGRES_DB" \
  | gzip > "$backup_file"

azcopy copy \
  "$backup_file" \
  "${AZURE_BLOB_CONTAINER_URL%/}/engine-${timestamp}.sql.gz${AZURE_BLOB_SAS_TOKEN}"
```

Protect the script:

```bash
chmod 700 /opt/engine/scripts/backup.sh
```

Run one manual backup before scheduling it:

```bash
/opt/engine/scripts/backup.sh
```

Schedule a nightly backup:

```bash
crontab -e
```

```cron
0 2 * * * /opt/engine/scripts/backup.sh >> /var/log/engine-backup.log 2>&1
```

The backup destination must be independent of the VPS. Test restoration
regularly on a separate PostgreSQL instance; a successful upload alone does
not prove that the backup is restorable.

## 9. Routine operational commands

```bash
cd /opt/engine

# Service status
docker compose ps

# Recent logs
docker compose logs --tail=100 backend

# Restart the backend
docker compose restart backend

# Check disk usage
df -h
docker system df
```

The production target is complete when `https://engine.miyeoh.com` reaches the
backend, PostgreSQL is not publicly exposed, the backend survives a container
restart, and a PostgreSQL backup can be restored from Azure Blob Storage.

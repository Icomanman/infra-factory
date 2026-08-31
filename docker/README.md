# Docker Runtime

This directory contains the runtime definition for the production application
stack. It is separate from the application source code and from the future
Terraform infrastructure definition.

The target runtime is:

```text
engine.miyeoh.com
        |
        v
      Caddy
        |
        v
    Backend API
        |
        v
    PostgreSQL
        |
        v
  Azure Blob Storage
  (database backups)
```

## Files

| File | Responsibility |
|---|---|
| `compose.yaml` | Defines the PostgreSQL, backend, and Caddy services |
| `Caddyfile` | Routes `engine.miyeoh.com` to the backend and terminates HTTPS |
| `.env.example` | Documents required runtime variables without containing secrets |
| `scripts/` | Operational scripts such as database backups |

The backend source and its `Dockerfile` belong to the application repository.
The Compose file should build that source or reference its published image.

## Expected VPS layout

Clone this infrastructure repository on the VPS:

```text
/opt/engine/
└── infra-factory/
    └── docker/
```

The backend source can be checked out beside the Docker configuration:

```text
/opt/engine/
├── infra-factory/
│   └── docker/
└── backend/
```

If `compose.yaml` uses `build: ../backend`, run Compose from this directory or
use the file's absolute project path consistently. Keep production `.env`
files on the VPS and out of Git.

## First-time setup

From the VPS:

```bash
sudo mkdir -p /opt/engine
sudo chown -R "$USER":"$USER" /opt/engine
cd /opt/engine

git clone https://github.com/OWNER/infra-factory.git
git clone https://github.com/OWNER/BACKEND_REPOSITORY.git backend

cd /opt/engine/infra-factory/docker
cp .env.example .env
chmod 600 .env
```

Edit `.env` and provide the real database credentials, backend configuration,
public domain, and Azure Blob Storage backup destination. Do not use example
passwords or commit the resulting `.env` file.

Before starting the stack, verify that:

- the backend repository contains a working `Dockerfile`;
- the backend listens on the port configured in `.env`;
- `engine.miyeoh.com` resolves to the VPS;
- the VPS firewall allows ports `80` and `443`; and
- the required database migration command is known.

## Start the stack

Validate the Compose file and environment expansion:

```bash
cd /opt/engine/infra-factory/docker
docker compose config
```

Start PostgreSQL first:

```bash
docker compose up -d postgres
docker compose ps
```

Run the backend migration command once PostgreSQL is healthy. The command is
defined by the backend framework, for example:

```bash
docker compose run --rm backend <backend-migration-command>
```

Then build and start the application:

```bash
docker compose up -d --build backend caddy
docker compose ps
```

Check logs:

```bash
docker compose logs --tail=100 postgres
docker compose logs --tail=100 backend
docker compose logs --tail=100 caddy
```

Test the public endpoint:

```bash
curl --fail-with-body https://engine.miyeoh.com/
```

## Updating the deployment

Update the infrastructure configuration:

```bash
cd /opt/engine/infra-factory
git pull --ff-only
```

Update the backend source:

```bash
cd /opt/engine/backend
git pull --ff-only
```

Rebuild and recreate only the backend:

```bash
cd /opt/engine/infra-factory/docker
docker compose up -d --build backend
```

Run migrations after releases that change the database schema.

Do not run `docker compose down -v` in production. The `-v` option removes
named volumes and can delete PostgreSQL data.

## PostgreSQL administration

For quick administration, connect to the existing database container:

```bash
cd /opt/engine/infra-factory/docker
docker compose exec postgres psql -U engine -d engine
```

For a local GUI client, publish PostgreSQL only on the VPS loopback address in
`compose.yaml`:

```yaml
ports:
  - "127.0.0.1:5433:5432"
```

Then create a tunnel from the local machine:

```bash
ssh -N -L 5433:127.0.0.1:5433 mico@YOUR_SERVER_IP
```

Connect the local client to `127.0.0.1:5433`. This reaches the same PostgreSQL
container and named volume without exposing port `5432` publicly.

## Database schema

The application should create and change tables through versioned migrations.
Do not rely on PostgreSQL image initialisation scripts for ongoing schema
changes; those scripts run only when the database volume is first created.

The deployment sequence is:

```text
Start PostgreSQL
    |
Wait for healthy status
    |
Run migrations
    |
Start or update backend
    |
Start Caddy
```

## Backups

The PostgreSQL Docker volume provides persistence, not an independent backup.
Use the script in `scripts/` to create a compressed `pg_dump`, then upload it
to Azure Blob Storage.

Backups must be tested by restoring one into a separate PostgreSQL instance.
The VPS copy alone is not sufficient protection against VPS or disk failure.

## Service boundaries

Only Caddy should publish host ports:

```text
Internet -> Caddy:80/443 -> backend -> postgres:5432
```

PostgreSQL should have no public host port mapping. The backend should use the
Compose service name `postgres` as its database hostname, not `localhost`.
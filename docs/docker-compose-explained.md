# Understanding the Docker Compose YAML

This note explains the `compose.yml` used by the production Docker setup in
[`docker-setup.md`](./docker-setup.md).

Docker Compose is a declarative description of a group of containers. It tells
Docker:

- which images to use or how to build them;
- which environment variables to pass;
- which containers depend on each other;
- which ports and networks to create;
- which storage must survive container replacement; and
- how containers should restart.

It is similar to other DevOps YAML files in that it describes desired state,
but it is not a script and it is not a CI workflow. Compose does not define
jobs, runners, or deployment triggers. Commands such as
`docker compose up -d` apply the YAML to the current Docker host.

## The complete shape

The file has two main parts:

```yaml
services:
  # Containers that make up the application

volumes:
  # Persistent Docker-managed storage

networks:
  # Container communication boundaries
```

`services` is the important section. Each key under it becomes a named
container service, such as `postgres`, `backend`, or `caddy`.

## The PostgreSQL service

```yaml
postgres:
  image: postgres:17
  restart: unless-stopped
  environment:
    POSTGRES_DB: ${POSTGRES_DB}
    POSTGRES_USER: ${POSTGRES_USER}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

### `image`

```yaml
image: postgres:17
```

This tells Docker to use the PostgreSQL image from a container registry.
`17` is the image tag, which selects the PostgreSQL major version.

An image is a packaged filesystem and its default startup command. A container
is a running instance created from that image.

Pinning a major version avoids silently moving to a different PostgreSQL major
version. For highly controlled deployments, pin an exact image digest as well.

### `restart`

```yaml
restart: unless-stopped
```

Docker restarts the container after a crash or VPS reboot, unless an operator
has explicitly stopped it.

This is a host-level restart policy. It is not the same as an application
health check: a running but unhealthy process may not be restarted solely
because it is unhealthy.

### `environment`

```yaml
environment:
  POSTGRES_DB: ${POSTGRES_DB}
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

The `${...}` values are read by Compose from the `.env` file or the shell
environment. They are substituted when Compose processes the YAML.

The resulting values are passed into the PostgreSQL container. The PostgreSQL
image uses these variables during initial database creation.

Changing these values later does not automatically change an already-created
database or user. PostgreSQL initialisation variables are primarily applied
when the data directory is empty.

## Persistent database storage

```yaml
volumes:
  - postgres_data:/var/lib/postgresql/data
```

The left side is a Docker volume name. The right side is the directory inside
the container where PostgreSQL stores its data.

The container can be removed and recreated without removing the database,
because the data lives in the named volume:

```text
postgres_data volume -> /var/lib/postgresql/data in postgres container
```

This is why the following command is dangerous in production:

```bash
docker compose down -v
```

The `-v` option removes the named volumes. `docker compose down` without `-v`
stops and removes containers while retaining named volumes.

## The PostgreSQL health check

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

This asks PostgreSQL whether it is accepting connections:

- `test` is the command executed inside the container;
- `interval` checks every 10 seconds;
- `timeout` allows 5 seconds for a response; and
- `retries` permits five failures before the service is marked unhealthy.

A health check reports service state. It does not replace database backups or
application-level checks.

## The backend service

```yaml
backend:
  build:
    context: ./backend
  restart: unless-stopped
  environment:
    DATABASE_URL: ${DATABASE_URL}
    PORT: ${BACKEND_PORT}
  expose:
    - "${BACKEND_PORT}"
```

### `build`

```yaml
build:
  context: ./backend
```

Compose builds the backend image from the `Dockerfile` in
`/opt/engine/backend`.

The context is the directory sent to Docker during the build. Files outside
the context cannot normally be copied by the Dockerfile. Keep the context
small and use a `.dockerignore` file in the backend repository.

This is analogous to a build step in GitHub Actions, except the build happens
on the VPS rather than on a CI runner.

### Backend environment

```yaml
environment:
  DATABASE_URL: ${DATABASE_URL}
  PORT: ${BACKEND_PORT}
```

The backend receives the database connection string and its listening port.
Inside Compose, `postgres` is a hostname provided by Docker DNS. Therefore the
database URL uses:

```text
postgres://...@postgres:5432/...
```

It must not use `localhost`. Inside the backend container, `localhost` means
the backend container itself, not the PostgreSQL container.

### `expose` versus `ports`

```yaml
expose:
  - "${BACKEND_PORT}"
```

`expose` makes the port available to other containers on the Docker network.
It does not publish the port on the VPS public interface.

By contrast:

```yaml
ports:
  - "80:80"
```

publishes a container port through the VPS. In this architecture only Caddy
uses `ports`; the backend remains behind the reverse proxy.

## Service startup dependencies

```yaml
depends_on:
  postgres:
    condition: service_healthy
```

This tells Compose to start PostgreSQL first and wait until its health check
passes before starting the backend.

It does not guarantee that the backend will never lose its database
connection. Applications should still handle connection retries and
temporary database unavailability.

## The Caddy service

```yaml
caddy:
  image: caddy:2
  restart: unless-stopped
  environment:
    DOMAIN: ${DOMAIN}
    BACKEND_PORT: ${BACKEND_PORT}
  ports:
    - "80:80"
    - "443:443"
```

Caddy is the public entry point:

- host port `80` maps to Caddy port `80`;
- host port `443` maps to Caddy port `443`; and
- Caddy forwards requests to the backend over the Docker network.

The environment variables are passed into Caddy because the `Caddyfile` uses
`{$DOMAIN}` and `{$BACKEND_PORT}` placeholders.

## Configuration and certificate volumes

```yaml
volumes:
  - ./Caddyfile:/etc/caddy/Caddyfile:ro
  - caddy_data:/data
  - caddy_config:/config
```

These are three different mount types:

| Mount | Meaning |
|---|---|
| `./Caddyfile:/etc/caddy/Caddyfile:ro` | Bind-mount the VPS file into the container, read-only |
| `caddy_data:/data` | Persist certificates and Caddy runtime data |
| `caddy_config:/config` | Persist Caddy configuration state |

The `:ro` suffix prevents Caddy from modifying the source `Caddyfile`.

Without the Caddy volumes, recreating the container could remove certificate
state and cause unnecessary certificate issuance.

## Networks

```yaml
networks:
  private:
    internal: true
  public:
```

Compose creates isolated virtual networks. Containers can communicate with
other containers on a shared network by service name.

The service assignments are:

```yaml
postgres:
  networks:
    - private

backend:
  networks:
    - private
    - public

caddy:
  networks:
    - public
```

This creates the intended path:

```text
Caddy -- public network -- backend -- private network -- PostgreSQL
```

The `internal: true` setting prevents the private network from providing
external connectivity. PostgreSQL is therefore not published to the Internet
and is not reachable by Caddy.

## Named volumes at the bottom of the file

```yaml
volumes:
  postgres_data:
  caddy_data:
  caddy_config:
```

These declarations tell Compose to create and manage the named volumes used by
the services. They are not folders in the Git repository.

List them with:

```bash
docker volume ls
```

Inspect one volume:

```bash
docker volume inspect postgres_data
```

Do not edit PostgreSQL volume files directly. Use PostgreSQL tools such as
`pg_dump` and restore procedures instead.

## How Compose commands map to the YAML

```bash
docker compose config
```

Parses the YAML and expands environment variables. Use it to catch malformed
YAML or missing values before changing containers.

```bash
docker compose up -d
```

Creates or updates the declared networks, volumes, and containers. `-d` runs
them in the background.

```bash
docker compose up -d --build backend
```

Rebuilds the backend image and recreates the backend container if necessary.

```bash
docker compose ps
```

Shows the current state of the Compose services.

```bash
docker compose logs --tail=100 backend
```

Displays recent backend logs.

```bash
docker compose pull
```

Downloads newer versions of registry-based images. It does not rebuild a
service that uses `build`.

```bash
docker compose down
```

Stops and removes the Compose containers and networks while retaining named
volumes.

## Compose versus GitHub Actions

These concerns should remain separate:

| GitHub Actions | Docker Compose |
|---|---|
| Trigger a workflow | Describe runtime services |
| Run jobs on a runner | Run containers on the VPS |
| Build and publish an image | Build or pull the image |
| Store CI secrets | Provide runtime environment variables |
| Deploy over SSH or another mechanism | Reconcile the VPS with `up` |

A later deployment workflow might do this:

```text
Git push
   |
GitHub Actions builds/tests the backend
   |
GitHub Actions connects to the VPS
   |
git pull
   |
docker compose up -d --build backend
```

Compose remains the description of how the application runs after deployment.
GitHub Actions is only the automation that invokes the deployment commands.

## The main safety rules

1. Keep PostgreSQL without a host `ports` mapping.
2. Keep database data in a named volume.
3. Keep secrets in `.env` or a proper secret-management system, never in Git.
4. Use service names such as `postgres` for container-to-container connections.
5. Run `docker compose config` before applying changes.
6. Never use `docker compose down -v` unless deleting the database is intended.
7. Treat backups and restore tests as separate from Docker volume persistence.

## Accessing a running service with `exec`

`docker compose exec` runs a command inside an already-running container
created by the Compose project. It does not create another container or another
database instance.

For example:

```bash
cd /opt/engine
docker compose exec postgres psql -U engine -d engine
```

This connects to the same PostgreSQL process, named volume, network, and
database used by the backend.

Other examples:

```bash
# List PostgreSQL tables
docker compose exec postgres psql -U engine -d engine -c '\dt'

# Open a shell inside the backend container
docker compose exec backend sh
```

The target service must already be running:

```bash
docker compose ps
docker compose up -d postgres
```

## `exec` versus `run`

These commands have different lifecycle behaviour:

```bash
docker compose exec backend npm run migrate
```

Runs the command inside the existing backend container.

```bash
docker compose run --rm backend npm run migrate
```

Creates a new temporary container from the backend service definition, runs the
command, and removes that temporary container afterwards.

Use `exec` for inspection and administration of a running service. Use `run`
for one-off tasks such as database migrations when those tasks should not
depend on the lifecycle of the long-running backend container:

```bash
docker compose up -d postgres
docker compose run --rm backend npm run migrate
docker compose up -d backend caddy
```

The migration command in this example is application-specific.

## Accessing PostgreSQL through an SSH tunnel

PostgreSQL should not be published on the VPS public interface. If a local
database client is needed, publish it only on the VPS loopback address:

```yaml
postgres:
  ports:
    - "127.0.0.1:5433:5432"
```

The left side is the VPS port and the right side is the PostgreSQL container
port. Apply the change on the VPS:

```bash
docker compose up -d postgres
```

From the local machine, create the tunnel:

```bash
ssh -N -L 5433:127.0.0.1:5433 mico@YOUR_SERVER_IP
```

Configure a local PostgreSQL client with:

```text
Host: 127.0.0.1
Port: 5433
Database: engine
User: engine
Password: value from .env
```

The connection path is:

```text
Local database client
        |
        v
Localhost:5433
        |
SSH tunnel
        |
VPS localhost:5433
        |
PostgreSQL container:5432
```

This reaches the same PostgreSQL container and named volume used by the
backend. It does not create a second database instance and does not expose
PostgreSQL publicly.

## Infrastructure repository versus application repository

The Compose deployment files are infrastructure configuration and should be
maintained in the infrastructure repository:

```text
infra-repo/
├── compose.yml
├── Caddyfile
├── .env.example
├── scripts/
│   ├── backup.sh
│   └── deploy.sh
└── README.md
```

The backend source and its `Dockerfile` can remain in the application
repository. The infrastructure repository describes how the application,
PostgreSQL, and Caddy run together; it does not need to own the application's
business logic.

# Production VPS Setup Guide (First Docker Deployment)

## Background

This guide is for someone who:

- Has used cloud VMs (e.g. EC2).
- Understands SSH and Linux administration.
- Has deployed applications manually on VPS.
- Has used managed PostgreSQL.
- Understands basic networking concepts.
- Is learning Docker for the first time in a production environment.

The goal is not to learn every DevOps tool.

The goal is to build a simple, maintainable MVP production environment.

---

## The Mental Model Shift

### Traditional VPS Deployment

A typical manual deployment looks like:

```
Create VPS

↓

SSH into server

↓

Install packages

↓

Configure services

↓

Deploy application

↓

Maintain server manually
```

The problem:

The server accumulates history.

After months:

```
Ubuntu Server

- Installed runtime
- Changed configs
- Added packages
- Applied fixes
- Modified settings
```

The server works, but reproducing it is difficult.

---

### Docker Approach

Docker changes the model.

Instead of:

> "Configure a server until it works"

You define:

> "This is the state I want."

Example:

```
Ubuntu VPS

    |
    |
 Docker

    |
    |
 Containers

    ├── Backend API
    ├── PostgreSQL
    └── Reverse Proxy
```

The VPS becomes a simple runtime environment.

---

## Infrastructure Layers

A production system has multiple layers.

### Layer 1: Infrastructure

Responsible for creating:

- VPS
- Networking
- Firewall rules
- DNS

Possible future tool:

```
Terraform
```

---

### Layer 2: Application Runtime

Responsible for running:

- Backend
- Database
- Reverse proxy

Tool:

```
Docker Compose
```

---

### Layer 3: Deployment

Responsible for:

- Building application
- Publishing images
- Updating servers

Tools:

```
GitHub Actions
Docker Registry
```

---

## Target Architecture

```
Internet

    |
    |
 Cloudflare

    |
    |
 Ubuntu VPS

    |
    |
 Docker Compose

    |
    |
    ├── Reverse Proxy
    |
    ├── Backend API
    |
    └── PostgreSQL


        |
        |
        Backup

        |
        v

 Azure Blob Storage
```

---

### Step 1: Prepare VPS

Recommended:

- Ubuntu 24.04 LTS
- 2-4 vCPU
- 4-6 GB RAM
- SSH key authentication

Initial setup:

```bash
apt update
apt upgrade -y
```

---

### Step 2: Configure SSH

Generate SSH key locally:

```bash
ssh-keygen -t ed25519
```

Copy key:

```bash
ssh-copy-id root@SERVER_IP
```

Test:

```bash
ssh root@SERVER_IP
```

Disable password login after confirming SSH key access.

---

### Step 3: Create Normal User

Avoid daily root usage.

```bash
adduser appuser

usermod -aG sudo appuser
```

Copy SSH keys:

```bash
mkdir /home/appuser/.ssh

cp ~/.ssh/authorized_keys /home/appuser/.ssh/

chown -R appuser:appuser /home/appuser/.ssh
```

Login:

```bash
ssh appuser@SERVER_IP
```

---

### Step 4: Install Docker

Install:

```bash
curl -fsSL https://get.docker.com | sh
```

Allow user access:

```bash
sudo usermod -aG docker $USER
```

Logout/login.

Verify:

```bash
docker version
```

---

### Step 5: Understand Docker Concepts

#### Image

A packaged application.

Example:

```
postgres:17
```

---

#### Container

A running instance of an image.

Example:

```
PostgreSQL container
```

---

#### Volume

Persistent storage.

Important for databases.

Example:

```
Container

PostgreSQL

    |
    |
    v

Docker Volume

    |
    |
    v

Actual Disk
```

Deleting the container does not delete database data.

---

#### Network

Containers communicate internally.

Example:

```
Backend

   |
   |
   v

postgres:5432
```

No need to expose PostgreSQL publicly.

---

### Step 6: Create Application Definition

Example:

```
my-app/

├── docker-compose.yml
├── backend/
├── nginx/
├── scripts/
└── .env
```

---

### Step 7: Docker Compose

Example:

```yaml
services:

  postgres:

    image: postgres:17

    environment:

      POSTGRES_DB: app

      POSTGRES_USER: postgres

      POSTGRES_PASSWORD: password

    volumes:

      - postgres_data:/var/lib/postgresql/data


  backend:

    build: ./backend

    depends_on:

      - postgres


volumes:

  postgres_data:
```

Start:

```bash
docker compose up -d
```

Check:

```bash
docker ps
```

---

### Step 8: Reverse Proxy

A reverse proxy is the public entry point.

Concept:

```
User

 |

HTTPS

 |

Reverse Proxy

 |

Backend API
```

The backend does not need to directly expose itself.

Possible choices:

- Nginx
- Caddy
- Traefik

Start simple.

Learn one later.

---

### Step 9: Database Backups

Docker is not a backup system.

Use normal PostgreSQL backup practices.

Example:

```
PostgreSQL

    |

pg_dump

    |

gzip

    |

Azure Blob Storage
```

Example:

```bash
pg_dump database | gzip > backup.sql.gz
```

Schedule with cron:

```cron
0 2 * * * /scripts/backup.sh
```

---

### Step 10: Deployment Workflow

Manual:

```
SSH

↓

git pull

↓

docker compose up -d
```

Later:

```
git push

↓

GitHub Actions

↓

Build Docker image

↓

Deploy

↓

docker compose pull
```

---

### Step 11: Disaster Recovery

If VPS dies:

1. Create new VPS.
2. Install Docker.
3. Clone repository.
4. Restore environment variables.
5. Restore PostgreSQL backup.
6. Start:

```bash
docker compose up -d
```

Application returns.

---

## What To Learn First

Recommended order:

### Phase 1

Docker basics:

- images
- containers
- volumes
- networks

---

### Phase 2

Docker Compose:

- multi-container applications
- environment variables
- persistence

---

### Phase 3

Production concerns:

- backups
- logging
- monitoring
- HTTPS

---

### Phase 4

Automation:

- GitHub Actions
- Terraform
- Infrastructure as Code

---

## Avoid Early Complexity

Do not start with:

- Kubernetes
- complex orchestration
- microservices
- service meshes

For an MVP:

```
One VPS

+

Docker Compose

+

PostgreSQL

+

Backups
```

is enough.

---

## Final Architecture

```
Ubuntu VPS

├── Docker
│
├── Reverse Proxy
│
├── Backend API
│
└── PostgreSQL


        |

        |

Azure Blob Storage

(Database Backups)
```

The goal is not perfect infrastructure.

The goal is a repeatable, recoverable system that lets you ship.

Think of Docker as a better packaging and deployment mechanism—not as a replacement for Linux.

Your Linux knowledge still applies:

- SSH
- users
- permissions
- networking
- firewalls
- backups
- monitoring

The only thing changing is **where your applications run**.

Instead of installing software directly into Ubuntu, Docker runs isolated containers.

For an MVP, this provides:

- Portable deployments
- Easier disaster recovery
- Cleaner servers
- Simpler upgrades
- Less configuration drift

Keep your infrastructure simple:

```
Ubuntu
    │
Docker
├── PostgreSQL
├── Backend
└── Caddy
    │
Azure Blob Storage (Backups)
```

Resist the temptation to over-engineer.

One VPS.
One `docker-compose.yml`.
Nightly backups.
Ship the product.
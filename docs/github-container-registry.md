# Publishing Images to GitHub Container Registry

## Purpose

GitHub Container Registry (GHCR) stores built Docker images remotely. The
registry hostname is `ghcr.io`. This allows a deployment server to pull an
exact image version without receiving source code or building the application.

## Connection Model

```text
Local development machine
    |
    | docker build, docker tag, docker push
    v
GitHub Container Registry (ghcr.io)
    |
    | docker compose pull
    v
Deployment server
    |
    | docker compose up -d
    v
Running containers
```

The local image name is only meaningful on the local Docker installation. A
GHCR tag gives it a remote name and version:

```text
miyeoh-engine:local
    -> ghcr.io/<github-owner>/miyeoh-engine:0.1.0
```

Use lower-case names for the GitHub owner and image package.

## Authenticate for Publishing

Create a GitHub personal access token with `write:packages`. If the package is
private, the token must also be authorised to access its repository. Log in
without placing the token in shell history:

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
```

Docker prompts for the token as the password.

## Publish Locally Built Images

Build and tag the editor image:

```bash
cd /home/icomanman/dev/miyeoh-editor
npm run build
docker build -t miyeoh-editor:local .
docker tag miyeoh-editor:local ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-editor:0.1.0
docker push ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-editor:0.1.0
```

Build and tag the engine image:

```bash
cd /home/icomanman/dev/miyeoh-engine
docker build -t miyeoh-engine:local .
docker tag miyeoh-engine:local ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-engine:0.1.0
docker push ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-engine:0.1.0
```

These commands create two independent packages in GHCR. They do not start or
deploy containers.

## Deploy with Docker Compose

Reference the remote images from the deployment Compose file:

```yaml
services:
  editor:
    image: ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-editor:0.1.0

  engine:
    image: ghcr.io/YOUR_GITHUB_USERNAME/miyeoh-engine:0.1.0
```

On the deployment server, pull and start the specified versions:

```bash
docker compose pull
docker compose up -d
```

For public packages, the server does not need to authenticate. For private
packages, log in to GHCR on the server using a token with `read:packages`:

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
```

Do not store tokens in the Compose file or commit them to Git.

## Tag Policy

Use an immutable release tag, for example `0.1.0` or a Git commit SHA, for a
deployment. The tag identifies the exact image that will run.

Do not use `latest` as a deployment version. It is merely Docker's default tag
when no tag is given, and can be moved to a different image over time.

## Future CI/CD

CI/CD can later perform the same sequence automatically:

```text
commit or release tag
    -> build images
    -> tag with version and commit SHA
    -> push to GHCR
    -> deployment server pulls that exact tag
```

The manual workflow above establishes the image names, tags, registry access,
and Compose contract that a later GitHub Actions workflow can reuse.

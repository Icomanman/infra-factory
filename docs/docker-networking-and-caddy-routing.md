# Docker Networking and Caddy Routing

## Purpose

This note explains how Docker Compose services communicate and how the central
Caddy service exposes selected services to a browser. It applies to the Miyeoh
editor, engine, and other future application services.

## The Three Configuration Layers

Each layer has a different responsibility:

| Layer | Responsibility | Example |
| --- | --- | --- |
| Application Dockerfile | Starts the process and selects its container listening port. | Editor Caddy listens on `:80`. |
| Docker Compose | Creates a private network for services and optionally publishes host ports. | `80:80` exposes central Caddy. |
| Central Caddyfile | Receives public requests and forwards them to a named Compose service. | `reverse_proxy editor:80` |

The three layers must agree at each connection. They do not require one global
port number.

## Default Local Stack

```text
Browser: http://localhost
    |
    | host port 80
    v
Compose mapping: 80:80
    |
    | central Caddy container port 80
    v
Caddyfile listener: :80
    |
    | private Docker Compose network
    v
Caddyfile target: editor:80
    |
    | editor container port 80
    v
Editor Caddy serves the static site from /dist
```

The editor service Dockerfile has this runtime contract:

```dockerfile
EXPOSE 80
CMD ["caddy", "file-server", "--root", "/dist", "--listen", ":80"]
```

The central Caddyfile points to that actual listener:

```caddyfile
:80 {
    reverse_proxy editor:80
}
```

The `editor` name is the Compose service name. Docker Compose provides DNS for
that name on the private Compose network. It is not a public Internet hostname.

## Public and Private Ports

A Compose `ports` mapping has this shape:

```yaml
ports:
  - "HOST_PORT:CONTAINER_PORT"
```

For central Caddy:

```yaml
services:
  caddy:
    ports:
      - "80:80"
```

This publishes the host's port `80` and sends traffic to port `80` in the
central Caddy container.

The editor and engine normally do not need `ports`. They are reached only by
central Caddy over the Compose network:

```yaml
services:
  editor:
    # No ports mapping

  engine:
    # No ports mapping
```

`EXPOSE 80` in a Dockerfile documents the intended container port. It does not
publish the port to the host. Compose can use `expose` as additional
service-level documentation, but services on the same default Compose network
can communicate without it.

## Using Different Ports

Ports may differ at each hop provided the connecting configuration refers to
the correct port. For example, this stack exposes `8080` locally, has central
Caddy listen on `80`, and runs the editor service on `9000`:

```yaml
services:
  caddy:
    ports:
      - "8080:80"
```

```caddyfile
:80 {
    reverse_proxy editor:9000
}
```

```dockerfile
EXPOSE 9000
CMD ["caddy", "file-server", "--root", "/dist", "--listen", ":9000"]
```

Users visit `http://localhost:8080`. The editor process never needs to know
that host port. It only listens on `9000` in its own container.

## Engine Routing

The same model applies to the engine, which listens on its own private port:

```caddyfile
:80 {
    handle /v1/* {
        reverse_proxy engine:8787
    }

    handle {
        reverse_proxy editor:80
    }
}
```

This sends browser API requests to the engine without publishing engine port
`8787` to the host. The browser sees one origin, which avoids a cross-origin
configuration for the editor API calls.

## Production HTTPS

For a real domain, replace `:80` with the domain name:

```caddyfile
editor.example.com {
    handle /v1/* {
        reverse_proxy engine:8787
    }

    handle {
        reverse_proxy editor:80
    }
}
```

With public DNS pointing to the host and ports `80` and `443` published by the
central Caddy service, Caddy can obtain and renew HTTPS certificates
automatically.

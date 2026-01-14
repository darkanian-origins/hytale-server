<div align="center">

# Hytale Server

**A production-ready Docker image for hosting Hytale dedicated servers**

[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white)](https://docker.com)
[![Java](https://img.shields.io/badge/Java-25-ED8B00?logo=openjdk&logoColor=white)](https://adoptium.net)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

[Quick Start](#-quick-start) | [Configuration](#-configuration) | [Environment Variables](#-environment-variables) | [Volumes](#-volumes)

</div>

## Features

- **Auto-Download** - Automatically downloads and extracts the latest Hytale server
- **Environment Config** - Configure your server entirely through environment variables
- **Health Checks** - Built-in UDP health monitoring for orchestration platforms
- **Security Hardened** - Runs as non-root user with minimal privileges
- **Production Ready** - Includes security, network, and production audits
- **Graceful Shutdown** - Proper signal handling with `tini` init system

---

## Quick Start

### Docker Run

```bash
docker run -d \
  --name hytale-server \
  -p 5520:5520/udp \
  -v hytale-data:/home/container \
  -e HYTALE_SERVER_NAME="My Hytale Server" \
  -e HYTALE_MAX_PLAYERS=50 \
  ghcr.io/darkanian/hytale-server:latest
```

### Docker Compose

```yaml
services:
  hytale:
    image: ghcr.io/darkanian/hytale-server:latest
    container_name: hytale-server
    restart: unless-stopped
    ports:
      - "5520:5520/udp"
    volumes:
      - hytale-data:/home/container
    environment:
      # Server Settings
      HYTALE_SERVER_NAME: "My Hytale Server"
      HYTALE_MAX_PLAYERS: 50
      HYTALE_GAMEMODE: "Adventure"

      # Performance
      JAVA_ARGS: "-Xms2G -Xmx4G"

      # Optional Features
      HYTALE_BACKUP: "TRUE"
      HYTALE_BACKUP_FREQUENCY: "3600"

volumes:
  hytale-data:
```

---

## Configuration

### Server Startup Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      STARTUP SEQUENCE                       │
├─────────────────────────────────────────────────────────────┤
│  1. Audit Suite        Security, Network, Production checks │
│  2. Hytale Downloader  Downloads server if not present      │
│  3. Config Management  Applies environment overrides        │
│  4. JVM Flags          Configures Java runtime flags        │
│  5. Process Execution  Launches Hytale server               │
└─────────────────────────────────────────────────────────────┘
```

### Config File

The server configuration is stored at `/home/container/config.json`. You can either:

1. **Use Environment Variables** - Set `HYTALE_*` variables to override config values
2. **Mount a Custom Config** - Mount your own `config.json` file

Environment variables take precedence and will overwrite values in the config file on each startup.

---

## Environment Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | `5520` | UDP port the server listens on |
| `SERVER_IP` | `0.0.0.0` | IP address to bind to |
| `JAVA_ARGS` | ` ` | Additional JVM arguments (e.g., `-Xms2G -Xmx4G`) |
| `DEBUG` | `FALSE` | Enable debug mode (runs security & network audits) |
| `PROD` | `FALSE` | Enable production mode (runs production audits) |

### Server Configuration

These variables override values in `config.json`:

| Variable | Config Key | Description |
|----------|------------|-------------|
| `HYTALE_SERVER_NAME` | `ServerName` | Display name of your server |
| `HYTALE_MOTD` | `MOTD` | Message of the day |
| `HYTALE_PASSWORD` | `Password` | Server password (leave empty for public) |
| `HYTALE_MAX_PLAYERS` | `MaxPlayers` | Maximum concurrent players |
| `HYTALE_MAX_VIEW_RADIUS` | `MaxViewRadius` | Maximum view distance |
| `HYTALE_COMPRESSION` | `LocalCompressionEnabled` | Enable local compression (`true`/`false`) |
| `HYTALE_WORLD` | `Defaults.World` | Default world name |
| `HYTALE_GAMEMODE` | `Defaults.GameMode` | Default game mode (`Adventure`, `Creative`, etc.) |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE` | `FALSE` | Enable AOT cache for faster startups |
| `HYTALE_ACCEPT_EARLY_PLUGINS` | `FALSE` | Allow early plugin loading |
| `HYTALE_ALLOW_OP` | `FALSE` | Enable operator commands |
| `HYTALE_AUTH_MODE` | `FALSE` | Enable authentication mode |
| `HYTALE_BACKUP` | `FALSE` | Enable automatic backups |
| `HYTALE_BACKUP_FREQUENCY` | ` ` | Backup interval in seconds |

---

## Volumes

| Path | Description |
|------|-------------|
| `/home/container` | Main data directory (worlds, config, etc.) |
| `/home/container/game` | Game files and server JAR |
| `/home/container/config.json` | Server configuration file |

### Recommended Volume Setup

```yaml
volumes:
  # Named volume for all server data
  - hytale-data:/home/container

  # Or bind mount for easy access
  - ./server-data:/home/container
```

---

## Health Checks

The container includes a built-in health check that monitors the UDP port:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=2m --retries=3 \
    CMD ss -ulpn | grep -q ":${SERVER_PORT}" || exit 1
```

Check container health:

```bash
docker inspect --format='{{.State.Health.Status}}' hytale-server
```

---

## Building Locally

```bash
# Clone the repository
git clone https://github.com/darkanian/hytale-server.git
cd hytale-server

# Build the image
docker build -t hytale-server:local .

# Run with local build
docker run -d \
  --name hytale-server \
  -p 5520:5520/udp \
  -v hytale-data:/home/container \
  hytale-server:local
```

---

## Architecture Support

| Architecture | Status |
|--------------|--------|
| `x86_64` / `amd64` | Supported |
| `arm64` / `aarch64` | Not yet supported (waiting for Hytale) |

---

## Troubleshooting

### Enable Debug Mode

```bash
docker run -e DEBUG=TRUE -e PROD=TRUE ...
```

This runs additional audits:
- **Security Audit** - File permissions, container hardening, clock sync
- **Network Audit** - Connectivity, port availability, UDP stack
- **Production Audit** - Memory limits, system resources, filesystem

### View Logs

```bash
# Follow logs
docker logs -f hytale-server

# Last 100 lines
docker logs --tail 100 hytale-server
```

### Access Container Shell

```bash
docker exec -it hytale-server /bin/sh
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**[Back to Top](#hytale-server)**

</div>

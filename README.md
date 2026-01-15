<div align="center">

# Hytale Server

**A production-ready Docker image for hosting Hytale dedicated servers**

[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white)](https://docker.com)
[![Java](https://img.shields.io/badge/Java-25-ED8B00?logo=openjdk&logoColor=white)](https://adoptium.net)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

[Quick Start](#-quick-start) | [Configuration](#-configuration) | [Environment Variables](#-environment-variables) | [Authentication](#authentication) | [Volumes](#-volumes)

</div>

## Features

- **Auto-Download** - Automatically downloads and extracts the latest Hytale server
- **Simple Configuration** - Easy-to-use environment variables (no JVM knowledge required)
- **OAuth Authentication** - Helper script for easy OAuth 2.0 device code flow
- **Hosting Platform Ready** - Works with Coolify, Portainer, and other Docker platforms
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
  -e MEMORY=4G \
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
      # Resources (simple format: "2G", "4G", "512M")
      MEMORY: "4G"

      # Server Settings
      HYTALE_SERVER_NAME: "My Hytale Server"
      HYTALE_MAX_PLAYERS: 50
      HYTALE_GAMEMODE: "Adventure"

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

### Resource Settings

Simple memory configuration - no JVM knowledge required:

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY` | ` ` | Server memory (e.g., `4G`, `2G`, `512M`) - sets both min and max |
| `MEMORY_MIN` | ` ` | Minimum memory (e.g., `2G`) - use for fine-tuned control |
| `MEMORY_MAX` | ` ` | Maximum memory (e.g., `4G`) - use for fine-tuned control |
| `JAVA_ARGS` | ` ` | Additional JVM arguments (advanced users only) |

**Examples:**
- `MEMORY=4G` - Simple: allocates 4GB to the server
- `MEMORY_MIN=2G` + `MEMORY_MAX=6G` - Advanced: start with 2GB, grow up to 6GB

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | `5520` | UDP port the server listens on |
| `SERVER_IP` | `0.0.0.0` | IP address to bind to |
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

### OAuth Authentication

| Variable | Description |
|----------|-------------|
| `HYTALE_PROFILE` | Profile username (if you have multiple Hytale profiles) |
| `HYTALE_SERVER_SESSION_TOKEN` | Session JWT (skips interactive auth) |
| `HYTALE_SERVER_IDENTITY_TOKEN` | Identity JWT (skips interactive auth) |

---

## Authentication

Hytale servers use OAuth 2.0 for authentication. This image includes automatic token caching - authenticate once and credentials are saved for future restarts.

### First-Time Setup

1. **Start the server**:

```bash
docker compose up -d
```

2. **Watch the logs for the auth prompt**:

```bash
docker logs -f hytale-server
```

3. **Follow the authentication link** displayed in the logs:

```
════════════════════════════════════════════════════════════════
              HYTALE SERVER AUTHENTICATION REQUIRED
════════════════════════════════════════════════════════════════

  Visit: https://accounts.hytale.com/device?user_code=ABCD-1234

════════════════════════════════════════════════════════════════
```

4. **Done!** - Credentials are cached automatically. Future restarts will use the cached tokens.

### How Token Caching Works

| What's Cached | TTL | Location |
|---------------|-----|----------|
| Refresh Token | 30 days | `.hytale-auth-cache.json` in volume |
| Profile UUID | Permanent | Same file |

On each startup:
1. Loads cached refresh token
2. Gets fresh access token
3. Creates new game session
4. Passes session tokens to server

### Alternative: Token Passthrough

For automated deployments, you can pass tokens directly via environment variables:

```bash
# Get tokens using the helper script
./scripts/hytale/hytale-auth.sh login
./scripts/hytale/hytale-auth.sh session
./scripts/hytale/hytale-auth.sh env
```

Then add to your configuration:

```yaml
environment:
  HYTALE_SERVER_SESSION_TOKEN: "eyJhbGciOi..."
  HYTALE_SERVER_IDENTITY_TOKEN: "eyJhbGciOi..."
  HYTALE_OWNER_UUID: "123e4567-e89b-12d3-a456-426614174000"
```

### Token Lifecycle

| Token | TTL | Notes |
|-------|-----|-------|
| OAuth Access Token | 1 hour | Used to create game sessions |
| OAuth Refresh Token | 30 days | Used to obtain new access tokens |
| Game Session | 1 hour | Auto-refreshed by server |

### Console Auth Commands

| Command | Description |
|---------|-------------|
| `/auth login device` | Start device code flow |
| `/auth status` | Check authentication status |
| `/auth logout` | Clear authentication |

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

### Pterodactyl / Pelican

Import the included egg for Pterodactyl or Pelican panel:

1. Download `egg-hytale.json` from this repository
2. Go to **Admin** → **Nests** → **Import Egg**
3. Upload the JSON file
4. Create a new server using the Hytale egg

**Variables available in the panel:**
- Server Name, Max Players, Game Mode, MOTD
- Server Password (leave empty for public)
- Auth Flags (defaults to `--auth-persistence Encrypted`)
- Java Arguments (optional)

After first start, use the console to authenticate:
```
/auth login device
```

---

### Podman

This image is compatible with Podman. Use `podman-compose` or run directly:

```bash
# Build with Podman
podman build -t hytale-server:local .

# Run with Podman
podman run -d \
  --name hytale-server \
  -p 5520:5520/udp \
  -v hytale-data:/home/container \
  hytale-server:local

# Or use podman-compose
podman-compose up -d
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

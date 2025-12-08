# MCP Gateway - Current Deployed State

> Snapshot taken: 2025-12-07 (updated 2025-12-08 with JWT auth + Obsidian MCP)
> Location: Unraid server @ ${UNRAID_IP}

## Architecture Overview

```
Internet
    │
    ▼ (Tailscale Funnel)
┌─────────────────────────────────────────────────────────────────────────┐
│  mcp-gateway.${TAILNET_DOMAIN}:443                                      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  tailscale-mcp (172.19.0.4)                                       │  │
│  │    Route: /     → http://authelia:9091                            │  │
│  │    Route: /mcp  → http://agentgateway:8080                        │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│         ┌────────────────────┴────────────────────┐                     │
│         ▼                                         ▼                     │
│  ┌─────────────────────┐                 ┌─────────────────────┐        │
│  │ authelia (172.19.0.5)│                │ agentgateway        │        │
│  │ Port: 9091           │                │ (172.19.0.3)        │        │
│  │ OIDC Provider        │                │ Port: 8080          │        │
│  │                      │                │ Admin: 15000        │        │
│  │ Client: claude-mcp-  │                │                     │        │
│  │         client       │                │ Backend:            │        │
│  └──────────┬───────────┘                │  └─ everything      │        │
│             │                            │     (mcp-everything │        │
│             ▼                            │      :3000/mcp)     │        │
│  ┌─────────────────────┐                 └──────────┬──────────┘        │
│  │ redis-mcp           │                            │                   │
│  │ (172.19.0.2)        │                            ▼                   │
│  │ Session storage     │                 ┌─────────────────────┐        │
│  └─────────────────────┘                 │ mcp-everything      │        │
│                                          │ (172.19.0.6)        │        │
│                                          │ Port: 3000          │        │
│                                          │ MCP test server     │        │
│                                          └─────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘
Network: mcp-net (172.19.0.0/16)
```

## Container Details

### tailscale-mcp

| Property | Value |
|----------|-------|
| Image | `tailscale/tailscale:latest` |
| IP | 172.19.0.4 |
| Ports | None exposed to host |
| State Dir | `/mnt/user/appdata/tailscale-mcp/state` |

**Environment Variables:**

```bash
TS_HOSTNAME=mcp-gateway
TS_EXTRA_ARGS=--advertise-tags=tag:funnel
TS_STATE_DIR=/var/lib/tailscale
TS_SERVE_CONFIG=/config/serve.json
TS_AUTHKEY=<redacted>
```

**serve.json** (`/mnt/user/appdata/tailscale-mcp/serve.json`):

```json
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "mcp-gateway.${TAILNET_DOMAIN}:443": {
      "Handlers": {
        "/mcp": {
          "Proxy": "http://agentgateway:8080"
        },
        "/": {
          "Proxy": "http://authelia:9091"
        }
      }
    }
  },
  "AllowFunnel": {
    "mcp-gateway.${TAILNET_DOMAIN}:443": true
  }
}
```

### authelia

| Property | Value |
|----------|-------|
| Image | `authelia/authelia:latest` |
| IP | 172.19.0.5 |
| Ports | 9091:9091 |
| Config Dir | `/mnt/user/appdata/authelia` |

**Environment Variables:**

```bash
TZ=America/Chicago
PUID=0
PGID=0
X_AUTHELIA_CONFIG=/config/configuration.yml
```

**Files:**

- `configuration.yml` - Main config (6028 bytes)
- `users.yml` - User database
- `jwks.pem` - RSA private key for OIDC signing
- `db.sqlite3` - Session/consent storage
- `notification.txt` - Email notifications (filesystem notifier)

**OIDC Configuration:**

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: "claude-mcp-client"
        client_name: "Claude.ai MCP"
        client_secret: '$argon2id$...'  # hashed
        public: false
        authorization_policy: "two_factor"
        redirect_uris:
          - "https://claude.ai/api/mcp/auth_callback"
          - "https://api.anthropic.com/oauth/callback"
        scopes:
          - "openid"
          - "profile"
          - "email"
          - "offline_access"
          - "address"
          - "phone"
          - "groups"
        grant_types:
          - "authorization_code"
          - "refresh_token"
        token_endpoint_auth_method: "client_secret_post"

    lifespans:
      access_token: 15m
      refresh_token: 1d
      id_token: 15m
```

**Session Configuration:**

```yaml
session:
  name: authelia_session
  same_site: strict
  expiration: 1h
  inactivity: 5m
  remember_me: 24h
  cookies:
    - domain: "${TAILNET_DOMAIN}"
      authelia_url: "https://mcp-gateway.${TAILNET_DOMAIN}"
  redis:
    host: redis-mcp
    port: 6379
```

**Users:**

```yaml
users:
  <username>:
    displayname: "<display-name>"
    email: "<email>"
    password: "$argon2id$..."  # hashed
    groups:
      - admins
      - mcp-users
```

### agentgateway

| Property | Value |
|----------|-------|
| Image | `ghcr.io/agentgateway/agentgateway:latest` |
| IP | 172.19.0.3 |
| Ports | 8080:8080, 15000:15000 |
| Config | `/mnt/user/appdata/agentgateway/config.yaml` |

**Environment Variables:**

```bash
ADMIN_ADDR=0.0.0.0:15000
OTEL_EXPORTER_OTLP_ENDPOINT=http://${UNRAID_IP}:4317
OTEL_SERVICE_NAME=agentgateway
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
```

**Volume Mounts:**

- `/mnt/user/appdata/agentgateway/config.yaml` → `/etc/agentgateway/config.yaml`
- `/mnt/user/appdata/agentgateway/jwks.json` → `/etc/agentgateway/jwks.json`

**config.yaml:**

```yaml
binds:
- port: 8080
  listeners:
  - routes:
    - policies:
        cors:
          allowOrigins:
            - "https://claude.ai"
            - "https://api.anthropic.com"
          allowHeaders:
            - "Authorization"
            - "Content-Type"
            - "Accept"
            - "X-Requested-With"
          allowMethods:
            - "GET"
            - "POST"
            - "OPTIONS"
        jwtAuth:
          mode: strict
          issuer: "https://mcp-gateway.${TAILNET_DOMAIN}"
          audiences:
            - "claude-mcp-client"
          jwks:
            file: /etc/agentgateway/jwks.json
      backends:
      - mcp:
          targets:
          - name: everything
            mcp:
              host: http://mcp-everything:3000/mcp
          - name: obsidian
            mcp:
              host: http://obsidian:3002/mcp
```

**jwks.json:** Fetched from Authelia at `http://localhost:9091/jwks.json`

**Admin UI:** http://${UNRAID_IP}:15000/ui

### mcp-everything

| Property | Value |
|----------|-------|
| Image | `node:20-alpine` |
| IP | 172.19.0.6 |
| Ports | None exposed to host |
| Command | `npx -y @modelcontextprotocol/server-everything streamableHttp` |

**Environment Variables:**

```bash
PORT=3000
```

### obsidian-mcp

| Property | Value |
|----------|-------|
| Image | `ghcr.io/cameronsjo/obsidian-mcp:latest` |
| Network | `container:obsidian` (shares network namespace) |
| Ports | 3002 (accessible via obsidian container) |

**Environment Variables:**

```bash
OBSIDIAN_API_KEY=<redacted>
OBSIDIAN_HOST=127.0.0.1
OBSIDIAN_USE_HTTP=true
PORT=3002
```

**Architecture:**

```
agentgateway ──HTTP──▶ obsidian:3002/mcp ──▶ supergateway ──stdio──▶ mcp-server ──REST──▶ 127.0.0.1:27123
```

Uses `--network container:obsidian` to share network namespace with VNC Obsidian, allowing access to localhost-bound REST API.

### obsidian (VNC)

| Property | Value |
|----------|-------|
| Image | `lscr.io/linuxserver/obsidian:latest` |
| IP | 172.19.0.7 |
| Ports | 3011:3000 (VNC web), 3012:3001 |
| Vault | `/mnt/user/appdata/obsidian/<vault-name>` |

**Local REST API Plugin:** Enabled on ports 27123 (HTTP) / 27124 (HTTPS), bound to 127.0.0.1

### redis-mcp

| Property | Value |
|----------|-------|
| Image | `redis:alpine` |
| IP | 172.19.0.2 |
| Ports | None exposed to host |
| Data Dir | `/mnt/user/appdata/redis-mcp` |

## Network

```
Network: mcp-net
Driver: bridge
Subnet: 172.19.0.0/16

Containers:
  - redis-mcp:      172.19.0.2
  - agentgateway:   172.19.0.3
  - tailscale-mcp:  172.19.0.4
  - authelia:       172.19.0.5
  - mcp-everything: 172.19.0.6
  - obsidian:       172.19.0.7 (+ obsidian-mcp via --network container:obsidian)
```

## Endpoints

| Endpoint | URL | Auth |
|----------|-----|------|
| MCP Gateway | https://mcp-gateway.${TAILNET_DOMAIN}/mcp | JWT (Bearer token from Authelia OIDC) |
| Authelia UI | https://mcp-gateway.${TAILNET_DOMAIN}/ | Form login + TOTP |
| OIDC Discovery | https://mcp-gateway.${TAILNET_DOMAIN}/.well-known/openid-configuration | Public |
| OIDC JWKS | https://mcp-gateway.${TAILNET_DOMAIN}/jwks.json | Public |
| agentgateway Admin | http://${UNRAID_IP}:15000/ui | Local only |

## Observability

SigNoz is deployed for centralized traces and metrics:

| Component | URL | Purpose |
|-----------|-----|---------|
| SigNoz UI | http://${UNRAID_IP}:3301 | Traces, metrics, logs dashboard |
| OTLP gRPC | http://${UNRAID_IP}:4317 | Telemetry ingestion |
| OTLP HTTP | http://${UNRAID_IP}:4318 | Telemetry ingestion |

**Location:** `/mnt/user/appdata/signoz/deploy/docker/`

agentgateway is configured to export OTEL traces/metrics to SigNoz via:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://${UNRAID_IP}:4317
OTEL_SERVICE_NAME=agentgateway
```

## Known Gaps

| Gap | Priority | Status |
|-----|----------|--------|
| ~~No JWT auth in agentgateway~~ | ~~p1~~ | **Done** (2025-12-08) |
| ~~Single test MCP backend only~~ | ~~p3~~ | **Done** - Obsidian MCP added |
| ~~No observability~~ | ~~p2~~ | **Done** (2025-12-08) - SigNoz deployed |
| No CEL authorization rules | p2 | Ready to implement |

## File Locations on Unraid

```
/mnt/user/appdata/
├── agentgateway/
│   ├── config.yaml              # agentgateway config
│   └── jwks.json                # JWKS from Authelia (for JWT validation)
├── authelia/
│   ├── configuration.yml        # Main Authelia config
│   ├── users.yml                # User database
│   ├── jwks.pem                 # OIDC signing key
│   ├── db.sqlite3               # Session storage
│   └── notification.txt         # Email queue
├── tailscale-mcp/
│   ├── serve.json               # Tailscale serve config
│   └── state/                   # Tailscale state
├── redis-mcp/                   # Redis persistence
├── obsidian/
│   └── <vault-name>/            # Obsidian vault data
├── signoz/
│   └── deploy/docker/           # SigNoz docker-compose stack
│       └── docker-compose.yaml
└── mcp-gateway-secrets.txt      # Generated secrets backup
```

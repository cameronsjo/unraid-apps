# Unraid MCP Gateway Deployment Guide

> This guide covers Unraid-specific deployment patterns for the MCP gateway stack.

## Unraid vs Standard Docker

Unraid has quirks that differ from standard Docker/Compose deployments:

| Aspect | Standard Docker | Unraid |
|--------|-----------------|--------|
| Compose | `docker-compose.yml` | Community Apps or manual containers |
| Data paths | `./data:/data` | `/mnt/user/appdata/<app>/` |
| Networking | Bridge by default | Custom networks via CLI |
| Permissions | Varies | Often root (PUID/PGID) |
| Management | CLI/Portainer | Unraid WebUI |

## Prerequisites

1. **Unraid 6.12+** with Docker enabled
2. **Tailscale container** or Tailscale on host
3. **User Scripts plugin** (optional, for automation)
4. **SSH access** to Unraid

## Directory Structure

Create the appdata structure:

```bash
ssh root@<unraid-ip>

# Create directories
mkdir -p /mnt/user/appdata/{agentgateway,authelia,tailscale-mcp,redis-mcp}

# Set permissions
chmod 700 /mnt/user/appdata/{agentgateway,authelia,tailscale-mcp}
```

Expected layout:

```
/mnt/user/appdata/
├── agentgateway/
│   └── config.yaml
├── authelia/
│   ├── configuration.yml
│   ├── users.yml
│   ├── jwks.pem          # Generated
│   └── db.sqlite3        # Auto-created
├── tailscale-mcp/
│   ├── serve.json
│   └── state/            # Auto-created
└── redis-mcp/            # Auto-created
```

## Network Setup

Create a dedicated Docker network for the MCP stack:

```bash
docker network create mcp-net
```

All containers in the stack should join this network to communicate by hostname.

## Container Deployment

### Option 1: Manual Docker Commands

Run each container manually (matches current deployed state):

#### 1. Redis

```bash
docker run -d \
  --name redis-mcp \
  --network mcp-net \
  --restart unless-stopped \
  -v /mnt/user/appdata/redis-mcp:/data \
  redis:alpine
```

#### 2. Authelia

```bash
docker run -d \
  --name authelia \
  --network mcp-net \
  --restart unless-stopped \
  -p 9091:9091 \
  -e TZ=America/Chicago \
  -e PUID=0 \
  -e PGID=0 \
  -v /mnt/user/appdata/authelia:/config \
  authelia/authelia:latest
```

#### 3. agentgateway

```bash
docker run -d \
  --name agentgateway \
  --network mcp-net \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 15000:15000 \
  -e ADMIN_ADDR=0.0.0.0:15000 \
  -v /mnt/user/appdata/agentgateway/config.yaml:/etc/agentgateway/config.yaml:ro \
  ghcr.io/agentgateway/agentgateway:latest \
  -f /etc/agentgateway/config.yaml
```

#### 4. MCP Backend (test server)

```bash
docker run -d \
  --name mcp-everything \
  --network mcp-net \
  --restart unless-stopped \
  -e PORT=3000 \
  node:20-alpine \
  sh -c "npx -y @modelcontextprotocol/server-everything streamableHttp"
```

#### 5. Tailscale (Funnel)

```bash
docker run -d \
  --name tailscale-mcp \
  --network mcp-net \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  -e TS_AUTHKEY=tskey-auth-xxxxx \
  -e TS_HOSTNAME=mcp-gateway \
  -e TS_EXTRA_ARGS=--advertise-tags=tag:funnel \
  -e TS_STATE_DIR=/var/lib/tailscale \
  -e TS_SERVE_CONFIG=/config/serve.json \
  -v /mnt/user/appdata/tailscale-mcp/state:/var/lib/tailscale \
  -v /mnt/user/appdata/tailscale-mcp/serve.json:/config/serve.json:ro \
  tailscale/tailscale:latest
```

### Option 2: Docker Compose

Create `/mnt/user/appdata/mcp-gateway/docker-compose.yml`:

```yaml
version: "3.8"

networks:
  mcp-net:
    driver: bridge

services:
  redis-mcp:
    image: redis:alpine
    container_name: redis-mcp
    restart: unless-stopped
    networks:
      - mcp-net
    volumes:
      - /mnt/user/appdata/redis-mcp:/data

  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    depends_on:
      - redis-mcp
    networks:
      - mcp-net
    ports:
      - "9091:9091"
    environment:
      - TZ=America/Chicago
      - PUID=0
      - PGID=0
    volumes:
      - /mnt/user/appdata/authelia:/config

  agentgateway:
    image: ghcr.io/agentgateway/agentgateway:latest
    container_name: agentgateway
    restart: unless-stopped
    networks:
      - mcp-net
    ports:
      - "8080:8080"
      - "15000:15000"
    environment:
      - ADMIN_ADDR=0.0.0.0:15000
    volumes:
      - /mnt/user/appdata/agentgateway/config.yaml:/etc/agentgateway/config.yaml:ro
    command: ["-f", "/etc/agentgateway/config.yaml"]

  mcp-everything:
    image: node:20-alpine
    container_name: mcp-everything
    restart: unless-stopped
    networks:
      - mcp-net
    environment:
      - PORT=3000
    command: ["sh", "-c", "npx -y @modelcontextprotocol/server-everything streamableHttp"]

  tailscale-mcp:
    image: tailscale/tailscale:latest
    container_name: tailscale-mcp
    restart: unless-stopped
    depends_on:
      - authelia
      - agentgateway
    networks:
      - mcp-net
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_HOSTNAME=mcp-gateway
      - TS_EXTRA_ARGS=--advertise-tags=tag:funnel
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_SERVE_CONFIG=/config/serve.json
    volumes:
      - /mnt/user/appdata/tailscale-mcp/state:/var/lib/tailscale
      - /mnt/user/appdata/tailscale-mcp/serve.json:/config/serve.json:ro
```

Deploy with:

```bash
cd /mnt/user/appdata/mcp-gateway
TS_AUTHKEY=tskey-auth-xxxxx docker-compose up -d
```

### Option 3: Community Applications

For Community Apps templates, see `templates/` directory (if available). Note that complex multi-container stacks like this are easier to manage via Compose or manual commands.

## Configuration Files

### agentgateway config.yaml

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
      backends:
      - mcp:
          targets:
          - name: everything
            mcp:
              host: http://mcp-everything:3000/mcp
```

### Tailscale serve.json

```json
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "mcp-gateway.<your-tailnet>.ts.net:443": {
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
    "mcp-gateway.<your-tailnet>.ts.net:443": true
  }
}
```

### Authelia configuration.yml

See `docs/deployment/current-state.md` for full config. Key sections:

- `session.cookies.domain` - Must match your tailnet
- `identity_providers.oidc.clients` - Claude.ai client config
- `session.redis` - Points to redis-mcp container

## Tailscale Auth Key

Generate an auth key with Funnel capability:

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Generate auth key with:
   - **Reusable**: Yes (for container restarts)
   - **Ephemeral**: No
   - **Tags**: `tag:funnel`
3. Ensure ACL allows funnel:

```json
{
  "nodeAttrs": [
    {
      "target": ["tag:funnel"],
      "attr": ["funnel"]
    }
  ]
}
```

## User Scripts (Optional)

Create a User Script for stack management:

**Script: mcp-gateway-restart**

```bash
#!/bin/bash
# Restart MCP Gateway stack

cd /mnt/user/appdata/mcp-gateway

# If using compose
docker-compose down
docker-compose up -d

# Or manual restart
# docker restart redis-mcp authelia agentgateway mcp-everything tailscale-mcp

echo "MCP Gateway stack restarted"
```

**Script: mcp-gateway-logs**

```bash
#!/bin/bash
# View recent logs from all MCP containers

for container in redis-mcp authelia agentgateway mcp-everything tailscale-mcp; do
  echo "=== $container ==="
  docker logs --tail 20 $container 2>&1
  echo ""
done
```

## Updating Containers

```bash
# Pull latest images
docker pull authelia/authelia:latest
docker pull ghcr.io/agentgateway/agentgateway:latest
docker pull tailscale/tailscale:latest
docker pull redis:alpine
docker pull node:20-alpine

# Recreate containers (compose method)
cd /mnt/user/appdata/mcp-gateway
docker-compose up -d --force-recreate

# Or manual method
docker stop agentgateway && docker rm agentgateway
# Re-run docker run command from above
```

## Backup

Important files to backup:

```bash
# Backup script
tar -czvf /mnt/user/backups/mcp-gateway-$(date +%Y%m%d).tar.gz \
  /mnt/user/appdata/agentgateway \
  /mnt/user/appdata/authelia \
  /mnt/user/appdata/tailscale-mcp/serve.json
```

**Do NOT backup:**

- `tailscale-mcp/state/` - Regenerated on auth
- `redis-mcp/` - Session cache, not critical
- `authelia/db.sqlite3` - Can be regenerated (loses active sessions)

## Common Issues

See `docs/deployment/troubleshooting.md` for detailed troubleshooting.

### Container Won't Start

```bash
# Check logs
docker logs <container-name>

# Check if port in use
netstat -tlnp | grep 8080
```

### Tailscale Not Connecting

```bash
# Check Tailscale status
docker exec tailscale-mcp tailscale status

# Re-authenticate
docker exec tailscale-mcp tailscale up --authkey=tskey-auth-xxxxx
```

### Network Issues

```bash
# Verify network exists
docker network ls | grep mcp-net

# Check container connectivity
docker exec agentgateway ping authelia
```

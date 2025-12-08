# Unraid-Specific Deployment Guide

This guide covers deploying the MCP Gateway stack on Unraid, addressing Unraid's specific quirks and best practices.

## Prerequisites

- Unraid 6.12+ (Docker support)
- SSH access enabled (Settings > Management Access)
- Community Applications plugin installed
- Tailscale account with Funnel-capable ACL

## Directory Structure

Unraid stores Docker persistent data in `/mnt/user/appdata/`. Create the following structure:

```bash
ssh root@<unraid-ip>

mkdir -p /mnt/user/appdata/agentgateway
mkdir -p /mnt/user/appdata/authelia
mkdir -p /mnt/user/appdata/tailscale-mcp/state
mkdir -p /mnt/user/appdata/redis-mcp
```

## Network Setup

Create a dedicated Docker network for the MCP stack:

```bash
docker network create mcp-net
```

## Container Deployment

Unraid doesn't natively support docker-compose in its GUI. You have three options:

### Option 1: Docker Compose Manager Plugin (Recommended)

1. Install "Docker Compose Manager" from Community Applications
2. Create compose file at `/mnt/user/appdata/mcp-gateway/docker-compose.yml`
3. Add stack via the plugin UI

### Option 2: User Scripts Plugin

1. Install "User Scripts" from Community Applications
2. Create a script to run docker-compose commands
3. Schedule or run manually

### Option 3: Manual Docker Run Commands

Run each container individually via Unraid's Docker tab or SSH.

## Container Configurations

### 1. Redis (Session Store)

```bash
docker run -d \
  --name redis-mcp \
  --network mcp-net \
  --restart unless-stopped \
  -v /mnt/user/appdata/redis-mcp:/data \
  redis:alpine
```

**Unraid Docker Template Settings:**

| Setting | Value |
|---------|-------|
| Name | redis-mcp |
| Repository | redis:alpine |
| Network Type | Custom: mcp-net |
| Path | /mnt/user/appdata/redis-mcp → /data |

### 2. Authelia (OIDC Provider)

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

**Required Config Files:**

Before starting, create these in `/mnt/user/appdata/authelia/`:

1. `configuration.yml` - Main config (see current-state.md)
2. `users.yml` - User database with argon2 hashed passwords
3. `jwks.pem` - RSA private key for OIDC (generate with openssl)

**Generate JWKS Key:**

```bash
openssl genrsa -out /mnt/user/appdata/authelia/jwks.pem 4096
```

**Generate Password Hash:**

```bash
docker run --rm authelia/authelia:latest \
  crypto hash generate argon2 --password 'your-password'
```

### 3. agentgateway (MCP Proxy)

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

**Admin UI Access:**

The admin UI is available at `http://<unraid-ip>:15000/ui` for local access only.

### 4. MCP Backend (Test Server)

```bash
docker run -d \
  --name mcp-everything \
  --network mcp-net \
  --restart unless-stopped \
  -e PORT=3000 \
  node:20-alpine \
  sh -c "npx -y @modelcontextprotocol/server-everything streamableHttp"
```

### 5. Tailscale (Funnel Ingress)

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

**Tailscale Auth Key:**

Generate at https://login.tailscale.com/admin/settings/keys:
- Check "Reusable"
- Check "Ephemeral" (optional)
- Ensure ACL allows Funnel for `tag:funnel`

**Tailscale ACL Requirements:**

```json
{
  "tagOwners": {
    "tag:funnel": ["autogroup:admin"]
  },
  "nodeAttrs": [
    {
      "target": ["tag:funnel"],
      "attr": ["funnel"]
    }
  ]
}
```

## Startup Order

Containers must start in this order due to dependencies:

1. `redis-mcp` - No dependencies
2. `authelia` - Depends on redis-mcp
3. `obsidian` - No dependencies (VNC container)
4. `obsidian-mcp` - Depends on obsidian (uses --network container:obsidian)
5. `mcp-everything` (or your MCP backends) - No dependencies
6. `agentgateway` - Depends on MCP backends
7. `tailscale-mcp` - Depends on authelia and agentgateway

**User Script for Ordered Startup:**

Create in User Scripts plugin:

```bash
#!/bin/bash
# MCP Gateway Stack Startup

# Wait for Docker
sleep 10

# Start in order
docker start redis-mcp
sleep 2
docker start authelia
sleep 3
docker start obsidian
sleep 5
docker start obsidian-mcp
sleep 2
docker start mcp-everything
sleep 2
docker start agentgateway
sleep 2
docker start tailscale-mcp

echo "MCP Gateway stack started"
```

Set to run "At Startup of Array".

**Note:** SigNoz runs as a separate docker-compose stack in `/mnt/user/appdata/signoz/deploy/docker/` and manages its own startup order.

## Unraid-Specific Considerations

### Path Mappings

Always use `/mnt/user/appdata/` for persistent storage. This ensures:
- Data survives container updates
- Proper permissions on Unraid
- Backup inclusion (if using Unraid backup plugins)

### Port Conflicts

Check for conflicts before assigning ports:

```bash
netstat -tlnp | grep -E '8080|9091|15000'
```

Common conflicts:
- 8080: Other web apps, Unraid WebUI alternate
- 9091: Transmission (if installed)

### Container Updates

Use Watchtower or manual updates. For the MCP stack:

```bash
# Pull latest images
docker pull authelia/authelia:latest
docker pull ghcr.io/agentgateway/agentgateway:latest
docker pull tailscale/tailscale:latest
docker pull redis:alpine

# Restart containers
docker restart redis-mcp authelia agentgateway tailscale-mcp
```

### Logs

View logs via Unraid Docker tab or SSH:

```bash
# All logs
docker logs -f agentgateway

# Last 50 lines
docker logs --tail 50 authelia

# Follow multiple
docker logs -f tailscale-mcp & docker logs -f agentgateway
```

### Backup

Include these paths in your Unraid backup:

```
/mnt/user/appdata/agentgateway/
/mnt/user/appdata/authelia/
/mnt/user/appdata/tailscale-mcp/
/mnt/user/appdata/redis-mcp/
```

**Exclude from backup** (regenerated on start):
- `authelia/db.sqlite3` (sessions - optional to backup)
- `tailscale-mcp/state/` (Tailscale can re-auth)

## Verifying the Stack

### 1. Check All Containers Running

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E 'mcp|authelia|redis|tailscale'
```

Expected output:
```
agentgateway        Up X hours
mcp-everything      Up X hours
authelia            Up X hours (healthy)
tailscale-mcp       Up X hours
redis-mcp           Up X hours
```

### 2. Check Network Connectivity

```bash
# From agentgateway, can reach MCP backend?
docker exec agentgateway wget -q -O - http://mcp-everything:3000/mcp || echo "Failed"

# From tailscale, can reach authelia?
docker exec tailscale-mcp wget -q -O - http://authelia:9091/.well-known/openid-configuration | head -1
```

### 3. Check Tailscale Funnel

```bash
docker exec tailscale-mcp tailscale status
docker exec tailscale-mcp tailscale serve status
```

### 4. External Test

From outside your network:
```bash
curl -s https://mcp-gateway.<your-tailnet>.ts.net/.well-known/openid-configuration | jq .issuer
```

## Common Issues

### Tailscale Won't Start Funnel

**Symptoms:** Container starts but Funnel not active

**Fix:**
1. Check ACL has funnel attribute for tag
2. Verify auth key has correct tags
3. Check serve.json syntax

```bash
docker logs tailscale-mcp 2>&1 | grep -i funnel
```

### Authelia 500 Errors

**Symptoms:** OIDC endpoints return 500

**Fix:**
1. Check Redis connection
2. Verify JWKS key exists and is valid
3. Check configuration.yml syntax

```bash
docker logs authelia 2>&1 | grep -i error
```

### agentgateway Can't Reach MCP Backend

**Symptoms:** Tools not loading, timeout errors

**Fix:**
1. Verify both on same network
2. Check MCP backend is listening on correct port
3. Test direct connectivity

```bash
docker exec agentgateway wget -q -O - http://mcp-everything:3000/mcp
```

# Unraid Deployment Guide for Claude

This project provides deployment patterns for a personal Unraid server. Use this guide when asked to deploy apps or MCP servers.

> **Secrets**: See `.claude/secrets.md` for IP addresses, Tailnet Domains, and other sensitive values.

## Server Details

- **Unraid IP**: `${UNRAID_IP}` (see `.claude/secrets.md`)
- **SSH Access**: `ssh root@${UNRAID_IP}` (or via Tailscale)
- **Tailnet**: `${TAILNET_DOMAIN}`
- **MCP Gateway**: `https://mcp-gateway.${TAILNET_DOMAIN}`

## Deployment Decision Tree

```
User wants to deploy something to Unraid
                │
                ▼
        ┌───────────────────┐
        │  Is it an MCP     │
        │  server for       │
        │  Claude.ai?       │
        └─────────┬─────────┘
                  │
          ┌───────┴───────┐
          │               │
         YES              NO
          │               │
          ▼               ▼
   ┌──────────────┐  ┌──────────────┐
   │ Add to MCP   │  │ Standalone   │
   │ Gateway      │  │ Docker App   │
   │              │  │              │
   │ See:         │  │ See:         │
   │ docs/deploy/ │  │ unraid-app-  │
   │ add-mcp.md   │  │ template/    │
   └──────────────┘  └──────────────┘
```

## Prerequisites Check

Before deploying, verify GHCR is configured on Unraid:

```bash
ssh root@${UNRAID_IP} "docker login ghcr.io --get-login 2>/dev/null && echo 'GHCR OK' || echo 'GHCR NOT CONFIGURED'"
```

If not configured, see [unraid-app-template/docs/deployment/ghcr-setup.md](unraid-app-template/docs/deployment/ghcr-setup.md).

## Quick Reference

### Deploy Standalone App

1. Build Docker image
2. Push to GHCR
3. Create `/mnt/user/appdata/<app>/docker-compose.yml`
4. Run `docker compose up -d`

See: [unraid-app-template/README.md](unraid-app-template/README.md)

### Deploy MCP Server to Gateway

1. Add service to gateway docker-compose or run standalone on `mcp-net`
2. Add target to agentgateway config
3. Fetch updated JWKS if needed
4. Restart agentgateway

See: [docs/deployment/add-mcp.md](docs/deployment/add-mcp.md)

## Current MCP Gateway State

The MCP gateway is already deployed and running:

| Component | Status | Notes |
|-----------|--------|-------|
| tailscale-mcp | Running | Funnel active on `${TAILNET_DOMAIN}` |
| authelia | Running | OIDC provider with TOTP |
| agentgateway | Running | JWT validation + OTEL export enabled |
| redis-mcp | Running | Session storage |
| mcp-everything | Running | Test MCP server |
| obsidian-mcp | Running | Vault access via REST API |
| obsidian | Running | VNC-based Obsidian (3011:3000) |
| signoz | Running | Observability stack (UI: 3301) |

**Current config location**: `/mnt/user/appdata/agentgateway/config.yaml`

See: [docs/deployment/current-state.md](docs/deployment/current-state.md)

## Commands

### Check gateway status

```bash
ssh root@${UNRAID_IP} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'mcp|authelia|redis|tailscale|obsidian'"
```

### View agentgateway logs

```bash
ssh root@${UNRAID_IP} "docker logs -f agentgateway"
```

### Restart after config change

```bash
ssh root@${UNRAID_IP} "docker restart agentgateway"
```

### Test JWT validation (should fail without token)

```bash
ssh root@${UNRAID_IP} "curl -s -X POST http://localhost:8080 -H 'Content-Type: application/json' -d '{}'"
# Expected: "authentication failure: no bearer token found"
```

## File Locations on Unraid

```text
/mnt/user/appdata/
├── agentgateway/
│   ├── config.yaml       # agentgateway routing + JWT config
│   └── jwks.json         # JWKS from Authelia
├── authelia/
│   ├── configuration.yml # OIDC config
│   └── users.yml         # User database
├── tailscale-mcp/
│   └── serve.json        # Funnel routing
├── obsidian/
│   └── <vault-name>/     # Obsidian vault
└── redis-mcp/            # Session data
```

## When to Update JWKS

If Authelia's OIDC signing key changes, update agentgateway's JWKS:

```bash
ssh root@${UNRAID_IP} "curl -s http://localhost:9091/jwks.json > /mnt/user/appdata/agentgateway/jwks.json && docker restart agentgateway"
```

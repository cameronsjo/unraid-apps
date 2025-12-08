# MCP Gateway Stack

Expose MCP servers to Claude.ai through an authenticated gateway on Unraid.

This is an advanced deployment pattern for running multiple MCP backends behind a single authenticated endpoint, without opening firewall ports or exposing services directly to the internet.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
│                                                                              │
│   [Claude.ai] ──────HTTPS──────► [Tailscale Funnel]                         │
│                                   mcp-gateway.YOUR_TAILNET.ts.net            │
└─────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              │ Outbound-only tunnel
                                              │ (no firewall ports needed)
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UNRAID SERVER                                   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        tailscale-mcp                                 │   │
│   │                       (ingress router)                               │   │
│   │                                                                      │   │
│   │   /auth/*  ──────►  Authelia (OIDC + TOTP)                          │   │
│   │   /mcp/*   ──────►  agentgateway (CEL authorization)                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    │ JWT validation via JWKS                 │
│                                    ▼                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         agentgateway                                 │   │
│   │                                                                      │   │
│   │   CEL Rules:                                                         │   │
│   │   - mcp.tool.name == "obsidian_search" && jwt.scope.contains(...)   │   │
│   │   - mcp.tool.name.startsWith("home_") && jwt.scope.contains(...)    │   │
│   └──────────────────────────────┬──────────────────────────────────────┘   │
│                                  │                                           │
│                    ┌─────────────┼─────────────┐                            │
│                    ▼             ▼             ▼                            │
│              ┌──────────┐ ┌──────────┐ ┌──────────┐                         │
│              │ Obsidian │ │   Home   │ │  Your    │                         │
│              │   MCP    │ │Assistant │ │  App     │                         │
│              │          │ │   MCP    │ │          │                         │
│              └──────────┘ └──────────┘ └──────────┘                         │
│                                                                              │
│              (Docker internal network - not exposed)                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Security Layers

| Layer | Component | Protection |
|-------|-----------|------------|
| **Transport** | Tailscale Funnel | Outbound-only tunnel, TLS terminates at Tailscale edge |
| **Authentication** | Authelia | OIDC provider with password + TOTP, credentials never touch LLM |
| **Authorization** | agentgateway | CEL rules enforce per-tool scope requirements |
| **Network** | Docker | MCP backends isolated on internal network |

## Why This Pattern?

### vs Direct Internet Exposure

| Aspect | Gateway Pattern | Direct Exposure |
|--------|-----------------|-----------------|
| Firewall ports | None (outbound only) | Inbound 443 required |
| Auth provider | Self-hosted (Authelia) | Third-party (Auth0, etc) |
| Monthly cost | $0 | $23+ (Auth0 paid tier) |
| Control | Full | Vendor policies |

### vs Standard MCP OAuth 2.1

MCP's OAuth 2.1 spec requires RFC 8707 (Resource Indicators) and RFC 7591 (Dynamic Client Registration). Authelia doesn't support these, but the gateway pattern sidesteps that:

| Requirement | Standard OAuth 2.1 | Gateway Pattern |
|-------------|-------------------|-----------------|
| RFC 8707 Resource Indicators | Auth server binds tokens to resources | agentgateway CEL rules handle scoping |
| RFC 7591 Dynamic Registration | Required for arbitrary clients | Not needed - Claude.ai is pre-configured |
| Token audience binding | Multiple resources need `aud` | Single gateway = single audience |

**Key insight:** agentgateway's CEL rules replace RFC 8707 with policy-as-code.

## Prerequisites

- Unraid server with Docker
- Tailscale account (free tier works)
- Domain knowledge of your MCP servers

## Quick Start

### 1. Generate Secrets

```bash
cd gateway

# Create secrets directory
mkdir -p authelia/secrets

# HMAC secret for JWT signing
openssl rand -hex 64 > authelia/secrets/hmac

# RSA key for OIDC
openssl genrsa -out authelia/secrets/issuer.pem 4096

# Or use the helper script
../scripts/generate-secrets.sh
```

### 2. Configure Users

Generate a password hash:

```bash
docker run --rm authelia/authelia:latest \
  crypto hash generate argon2 --password 'YOUR_PASSWORD'
```

Edit `authelia/users.yml`:

```yaml
users:
  admin:
    displayname: "Admin User"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # paste hash here
    email: admin@example.com
    groups:
      - admins
```

### 3. Configure OIDC Client

Generate a client secret hash:

```bash
docker run --rm authelia/authelia:latest \
  crypto hash generate pbkdf2 --password 'YOUR_CLIENT_SECRET'
```

The client secret hash goes in `authelia/configuration.yml` (already configured in template).

**Save the plaintext client secret** - Claude.ai will need it for OAuth.

### 4. Set Environment Variables

```bash
cp .env.example .env
vim .env
```

Required variables:

```bash
# Your Tailnet name (find at https://login.tailscale.com/admin/machines)
TAILNET_NAME=your-tailnet

# Tailscale auth key with Funnel capability
# Generate at: https://login.tailscale.com/admin/settings/keys
TS_AUTHKEY=tskey-auth-xxxxx

# OIDC client secret (plaintext, for agentgateway)
OIDC_CLIENT_SECRET=your-client-secret
```

### 5. Update Tailnet Name

Replace `YOUR_TAILNET` in all config files:

```bash
# macOS
find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
  -exec sed -i '' 's/YOUR_TAILNET/your-actual-tailnet/g' {} \;

# Linux
find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
  -exec sed -i 's/YOUR_TAILNET/your-actual-tailnet/g' {} \;
```

### 6. Deploy to Unraid

```bash
# Copy to Unraid
scp -r . root@tower:/mnt/user/appdata/mcp-gateway/

# SSH and start
tailscale ssh root@tower
cd /mnt/user/appdata/mcp-gateway
docker compose up -d
```

### 7. Verify

```bash
# Check Funnel is serving
curl https://mcp-gateway.YOUR_TAILNET.ts.net/auth/.well-known/openid-configuration

# Check agentgateway
curl https://mcp-gateway.YOUR_TAILNET.ts.net/health
```

## File Structure

```
gateway/
├── docker-compose.yml          # Full stack definition
├── tailscale-serve.json        # Funnel routing rules
├── agentgateway.yaml           # MCP routing + CEL authorization
├── .env.example                # Environment template
├── .gitignore                  # Exclude secrets
├── README.md                   # This file
└── authelia/
    ├── configuration.yml       # OIDC provider config
    ├── users.yml               # User database
    └── secrets/                # Generated secrets (gitignored)
        ├── hmac                # JWT signing key
        └── issuer.pem          # OIDC signing key
```

## Adding MCP Backends

### 1. Add Service to docker-compose.yml

```yaml
services:
  # ... existing services ...

  my-mcp-server:
    image: ghcr.io/YOUR_USERNAME/my-mcp-server:latest
    container_name: my-mcp-server
    restart: unless-stopped
    networks:
      - mcp-internal
    environment:
      - NODE_ENV=production
    # No ports exposed - only agentgateway reaches it
```

### 2. Add Target to agentgateway.yaml

```yaml
targets:
  # ... existing targets ...
  - name: my-mcp-server
    url: http://my-mcp-server:3000/mcp
```

### 3. Add CEL Authorization Rules

```yaml
mcpAuthorization:
  rules:
    # ... existing rules ...

    # Read-only access
    - 'mcp.tool.name.startsWith("myserver_read") && jwt.scope.contains("myserver:read")'

    # Write access
    - 'mcp.tool.name.startsWith("myserver_write") && jwt.scope.contains("myserver:write")'
```

### 4. Add Scopes to Authelia

```yaml
# authelia/configuration.yml
identity_providers:
  oidc:
    clients:
      - client_id: 'mcp-gateway'
        scopes:
          # ... existing scopes ...
          - 'myserver:read'
          - 'myserver:write'
```

### 5. Restart Stack

```bash
docker compose up -d
```

## Request Flow

1. **Claude initiates OAuth** → redirects to Authelia
2. **User authenticates** → password + TOTP
3. **Authelia issues JWT** → includes granted scopes
4. **Claude calls /mcp** → with `Authorization: Bearer <jwt>`
5. **agentgateway validates** → checks signature via JWKS
6. **CEL rules evaluate** → `mcp.tool.name` + `jwt.scope.contains()`
7. **Request routes** → to appropriate MCP backend
8. **Response returns** → same path back

## CEL Rule Reference

agentgateway provides these bindings for CEL expressions:

| Variable | Type | Description |
|----------|------|-------------|
| `mcp.tool.name` | string | The MCP tool being invoked |
| `jwt.scope` | list | Token scopes (use `.contains()`) |
| `jwt.sub` | string | Token subject (user ID) |
| `jwt.aud` | string | Token audience |

### Example Rules

```yaml
mcpAuthorization:
  rules:
    # Exact tool match
    - 'mcp.tool.name == "obsidian_search" && jwt.scope.contains("obsidian:read")'

    # Prefix match (all tools starting with "home_")
    - 'mcp.tool.name.startsWith("home_") && jwt.scope.contains("home:execute")'

    # Multiple scopes (either works)
    - 'mcp.tool.name == "admin_action" && (jwt.scope.contains("admin") || jwt.sub == "admin")'

    # Deny by default (implicit, but can be explicit)
    # Any request not matching above rules is denied
```

## Troubleshooting

### Funnel Not Working

```bash
# Check Tailscale container
docker logs tailscale-mcp

# Verify Funnel status
docker exec tailscale-mcp tailscale serve status

# Check serve config was applied
docker exec tailscale-mcp cat /config/serve.json
```

### JWT Validation Errors

```bash
# Check JWKS endpoint is accessible
curl http://authelia:9091/api/oidc/jwks  # from inside Docker network

# Via Funnel
curl https://mcp-gateway.YOUR_TAILNET.ts.net/auth/api/oidc/jwks

# Check agentgateway logs
docker logs agentgateway
```

### CEL Rules Not Matching

```bash
# Enable debug logging
# In agentgateway.yaml:
logging:
  level: debug

# Restart and check logs
docker compose restart agentgateway
docker logs -f agentgateway
```

### OIDC Discovery

```bash
# Authelia's discovery endpoint
curl https://mcp-gateway.YOUR_TAILNET.ts.net/auth/.well-known/openid-configuration
```

## Updating

### Pull New Images

```bash
docker compose pull
docker compose up -d
```

### Update Configuration

```bash
# Edit configs locally
vim agentgateway.yaml

# Copy to Unraid
scp agentgateway.yaml root@tower:/mnt/user/appdata/mcp-gateway/

# Restart affected service
tailscale ssh root@tower "cd /mnt/user/appdata/mcp-gateway && docker compose restart agentgateway"
```

## Backup

Critical files to backup:

```bash
# Secrets (required to decrypt existing sessions)
authelia/secrets/hmac
authelia/secrets/issuer.pem

# User database
authelia/users.yml

# Configuration
authelia/configuration.yml
agentgateway.yaml
docker-compose.yml
```

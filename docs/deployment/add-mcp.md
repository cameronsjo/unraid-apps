# Add MCP Server to Gateway

Quick guide for adding a new MCP server to the existing gateway on Unraid.

## Prerequisites

- MCP gateway stack already running (see [current-state.md](current-state.md))
- MCP server Docker image available (GHCR or local)
- SSH access to Unraid

## Steps

### 1. Add Service to Docker Network

SSH to Unraid and start your MCP server on the `mcp-net` network:

```bash
ssh root@${UNRAID_IP}

docker run -d \
  --name my-mcp-server \
  --network mcp-net \
  --restart unless-stopped \
  -e PORT=3000 \
  ghcr.io/YOUR_USERNAME/my-mcp-server:latest
```

**Important:** No ports need to be exposed - agentgateway reaches it via Docker network.

### 2. Update agentgateway Config

Edit the config to add your MCP server as a target:

```bash
ssh root@${UNRAID_IP}

cat >> /mnt/user/appdata/agentgateway/config.yaml << 'EOF'

# Note: This appends to the existing targets array
# You may need to edit the file manually to place correctly
EOF

# Actually edit the file:
vi /mnt/user/appdata/agentgateway/config.yaml
```

Add your server to the `targets` array:

```yaml
backends:
- mcp:
    targets:
    - name: everything
      mcp:
        host: http://mcp-everything:3000/mcp
    # ADD YOUR SERVER HERE:
    - name: myserver
      mcp:
        host: http://my-mcp-server:3000/mcp
```

**Target naming rules:**
- No underscores in target names (use hyphens)
- Tools will be prefixed: `myserver_<tool_name>`

### 3. Restart agentgateway

```bash
ssh root@${UNRAID_IP} "docker restart agentgateway"
```

### 4. Verify

Check logs for successful connection:

```bash
ssh root@${UNRAID_IP} "docker logs agentgateway 2>&1 | tail -20"
```

Test tool discovery (requires valid JWT, so just check no errors):

```bash
ssh root@${UNRAID_IP} "docker logs agentgateway 2>&1 | grep -i error | tail -5"
```

## Full Example: Adding Obsidian MCP

See [obsidian-mcp-architecture.md](obsidian-mcp-architecture.md) for detailed architecture.

**Special case:** Obsidian MCP uses `--network container:obsidian` to share network namespace with the VNC container, allowing access to the localhost-bound REST API.

### 1. Ensure Obsidian VNC is running on mcp-net

```bash
# Obsidian VNC should already be running and on mcp-net
docker ps | grep obsidian
```

### 2. Run Obsidian MCP container

```bash
ssh root@${UNRAID_IP}

docker run -d \
  --name obsidian-mcp \
  --network container:obsidian \
  --restart unless-stopped \
  -e OBSIDIAN_API_KEY=your-api-key \
  -e OBSIDIAN_HOST=127.0.0.1 \
  -e OBSIDIAN_USE_HTTP=true \
  -e PORT=3002 \
  ghcr.io/cameronsjo/obsidian-mcp:latest
```

### 3. Update agentgateway config

```yaml
# /mnt/user/appdata/agentgateway/config.yaml
backends:
- mcp:
    targets:
    - name: everything
      mcp:
        host: http://mcp-everything:3000/mcp
    - name: obsidian
      mcp:
        host: http://obsidian:3002/mcp  # Note: uses obsidian hostname, not obsidian-mcp
```

### 4. Restart

```bash
docker restart agentgateway
```

### 5. Tools now available

After restart, tools appear as:

- `obsidian_list_notes`
- `obsidian_read_note`
- `obsidian_update_note`
- `obsidian_global_search`
- `obsidian_manage_tags`
- etc.

## Adding Authorization Rules (Optional)

If you want to restrict tool access by JWT scope:

### 1. Add scope to Authelia

Edit `/mnt/user/appdata/authelia/configuration.yml`:

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: "claude-mcp-client"
        scopes:
          - "openid"
          - "profile"
          # ... existing scopes ...
          - "obsidian:read"   # ADD
          - "obsidian:write"  # ADD
```

### 2. Add CEL rules to agentgateway

Currently, JWT validation is enabled but no CEL rules for authorization. To add:

```yaml
# /mnt/user/appdata/agentgateway/config.yaml
binds:
- port: 8080
  listeners:
  - routes:
    - policies:
        # ... existing cors and jwtAuth ...
        authorization:
          rules:
            - 'mcp.tool.name.startsWith("obsidian_") && jwt.scope.contains("obsidian:read")'
      backends:
        # ...
```

### 3. Restart both

```bash
docker restart authelia agentgateway
```

## Removing an MCP Server

### 1. Remove from agentgateway config

Edit `/mnt/user/appdata/agentgateway/config.yaml` and remove the target.

### 2. Restart agentgateway

```bash
docker restart agentgateway
```

### 3. Stop and remove container

```bash
docker stop my-mcp-server
docker rm my-mcp-server
```

## Troubleshooting

### Container can't connect to MCP server

```bash
# Check both are on mcp-net
docker network inspect mcp-net --format '{{range .Containers}}{{.Name}} {{end}}'

# Test connectivity from agentgateway perspective
docker exec agentgateway wget -q -O - http://my-mcp-server:3000/health
```

### Tools not appearing

```bash
# Check MCP server is responding
docker logs my-mcp-server

# Check agentgateway can reach it
docker logs agentgateway 2>&1 | grep -i "my-mcp-server"
```

### Auth failures after adding authorization rules

```bash
# Check JWT has required scope
# Decode a token at jwt.io to see claims

# Check CEL rule syntax
docker logs agentgateway 2>&1 | grep -i cel
```

# MCP Gateway Troubleshooting Guide

## Quick Diagnostics

Run this to get a full status overview:

```bash
ssh root@<unraid-ip> << 'EOF'
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E 'mcp|authelia|redis|tailscale'

echo -e "\n=== Network ==="
docker network inspect mcp-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'

echo -e "\n=== Recent Errors ==="
docker logs agentgateway 2>&1 | grep -i error | tail -5
docker logs authelia 2>&1 | grep -i error | tail -5
docker logs tailscale-mcp 2>&1 | grep -i error | tail -5

echo -e "\n=== Tailscale Status ==="
docker exec tailscale-mcp tailscale status 2>/dev/null | head -10
EOF
```

## Testing the Full Flow

### 1. Test OIDC Discovery

```bash
# From anywhere with internet access
curl -s https://mcp-gateway.<tailnet>.ts.net/.well-known/openid-configuration | jq '.issuer, .authorization_endpoint'
```

**Expected:**
```json
"https://mcp-gateway.<tailnet>.ts.net"
"https://mcp-gateway.<tailnet>.ts.net/api/oidc/authorization"
```

**If it fails:**
- Check Tailscale Funnel is active
- Check authelia container is healthy
- Check serve.json routes `/` to authelia

### 2. Test MCP Endpoint

```bash
# Requires Accept header for SSE
curl -s -H "Accept: text/event-stream" https://mcp-gateway.<tailnet>.ts.net/mcp
```

**Expected:** `Session ID is required` or similar MCP protocol response

**If 404:** serve.json missing `/mcp` route
**If 502:** agentgateway not running or not reachable

### 3. Test Tool Discovery (Local)

```bash
ssh root@<unraid-ip>

# Initialize MCP session and list tools
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'
```

**Expected:** JSON response with server capabilities

### 4. Test from Claude.ai

1. Go to Claude.ai Settings > Integrations
2. Add MCP Server: `https://mcp-gateway.<tailnet>.ts.net/mcp`
3. Should redirect to Authelia login
4. After 2FA, tools should appear

## Common Issues

### Issue: "Not Acceptable: Client must accept text/event-stream"

**Cause:** MCP client not sending correct Accept header

**Fix:** This is expected for non-MCP requests. The MCP client (Claude.ai) sends the correct headers.

### Issue: "Session ID is required"

**Cause:** Missing MCP session initialization

**Fix:** This is normal for raw HTTP requests. MCP clients handle session management.

### Issue: Authelia returns 401 on OIDC endpoints

**Cause:** Access control blocking OIDC endpoints

**Check:**
```yaml
# In authelia configuration.yml
access_control:
  default_policy: two_factor
  # OIDC endpoints should NOT require auth
  # They handle their own auth via client credentials
```

**Fix:** Authelia OIDC endpoints are public by design - the 401 is for protected resources, not OIDC itself.

### Issue: Claude.ai shows "Tool execution failed"

**Possible causes:**
1. MCP backend crashed
2. agentgateway can't reach backend
3. CORS blocking response

**Debug:**
```bash
# Check agentgateway logs during tool call
docker logs -f agentgateway 2>&1 | grep -E 'error|failed|tools/call'

# Check MCP backend logs
docker logs -f mcp-everything
```

### Issue: OAuth flow doesn't redirect back to Claude

**Cause:** Redirect URI mismatch

**Check authelia configuration.yml:**
```yaml
clients:
  - client_id: "claude-mcp-client"
    redirect_uris:
      - "https://claude.ai/api/mcp/auth_callback"  # Must match exactly
```

### Issue: Tailscale container restarts repeatedly

**Cause:** Usually auth key issues

**Debug:**
```bash
docker logs tailscale-mcp 2>&1 | tail -20
```

**Common fixes:**
1. Regenerate auth key (may have expired)
2. Check auth key has correct tags
3. Verify ACL allows the tags

### Issue: "invalid_client" on OAuth token exchange

**Cause:** Client secret mismatch

**Debug:**
1. Verify client_secret in authelia is the *hashed* version
2. Verify the plaintext secret matches what Claude.ai sends

**Regenerate:**
```bash
# Generate new secret
openssl rand -base64 32

# Hash it for authelia
docker run --rm authelia/authelia:latest \
  crypto hash generate argon2 --password '<plaintext-secret>'
```

### Issue: agentgateway admin UI not accessible

**Cause:** Port not exposed or firewall

**Fix:**
```bash
# Check port binding
docker inspect agentgateway --format '{{json .HostConfig.PortBindings}}'
# Should show: "15000/tcp":[{"HostIp":"","HostPort":"15000"}]

# Test locally on Unraid
curl http://localhost:15000/ui
```

## Log Analysis

### agentgateway Logs

```bash
docker logs agentgateway 2>&1 | tail -50
```

**Key patterns:**
- `protocol=mcp mcp.method=tools/list` - Tool discovery
- `protocol=mcp mcp.method=tools/call` - Tool execution
- `http.status=200` - Success
- `http.status=406` - Wrong Accept header
- `http.status=422` - Invalid request

### Authelia Logs

```bash
docker logs authelia 2>&1 | tail -50
```

**Key patterns:**
- `level=info msg="Access to..." method=GET` - Access granted
- `level=warning msg="Access to..." method=GET` - Access denied
- `level=error` - Configuration or runtime errors

### Tailscale Logs

```bash
docker logs tailscale-mcp 2>&1 | tail -50
```

**Key patterns:**
- `Logged in` - Successfully authenticated
- `Funnel` - Funnel status
- `serve: ...` - Serve proxy status

## Health Checks

### Authelia Health

```bash
docker inspect authelia --format '{{.State.Health.Status}}'
# Should be: healthy

# Manual check
curl -s http://localhost:9091/api/health | jq .
```

### Redis Health

```bash
docker exec redis-mcp redis-cli ping
# Should return: PONG
```

### agentgateway Readiness

```bash
curl -s http://localhost:15021/ready
# Should return empty 200
```

## Reset Procedures

### Reset Authelia Sessions

```bash
# Stop authelia
docker stop authelia

# Remove session database
rm /mnt/user/appdata/authelia/db.sqlite3

# Restart
docker start authelia
```

### Reset Tailscale State

```bash
# Stop tailscale
docker stop tailscale-mcp

# Remove state
rm -rf /mnt/user/appdata/tailscale-mcp/state/*

# Generate new auth key and update container
# Restart
docker start tailscale-mcp
```

### Full Stack Restart

```bash
docker restart redis-mcp authelia mcp-everything agentgateway tailscale-mcp
```

## Performance Debugging

### Check Response Times

```bash
docker logs agentgateway 2>&1 | grep 'duration=' | tail -20
```

**Normal:** 1-50ms for most operations
**Slow:** >1000ms indicates backend issues

### Check Memory Usage

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | grep -E 'mcp|authelia|redis|tailscale'
```

### Check Network Latency

```bash
# From agentgateway to MCP backend
docker exec agentgateway sh -c "time wget -q -O /dev/null http://mcp-everything:3000/mcp"
```

## Getting Help

1. **agentgateway issues:** https://github.com/agentgateway/agentgateway/issues
2. **Authelia issues:** https://github.com/authelia/authelia/issues
3. **Tailscale Funnel:** https://tailscale.com/kb/1223/funnel
4. **MCP Protocol:** https://modelcontextprotocol.io/docs

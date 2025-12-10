# Authelia OIDC Troubleshooting

Common issues and fixes when using Authelia as an OIDC provider for Claude.ai MCP.

## Issue: "scope 'address' is not allowed"

**Symptom**: OAuth flow fails with error about invalid/unknown scope.

**Cause**: Claude.ai requests these OIDC scopes: `openid`, `profile`, `email`, `address`, `phone`, `groups`, `offline_access`. If any are missing from the client config, auth fails.

**Fix**: Ensure all scopes are listed in the client configuration:

```yaml
clients:
  - client_id: "claude-mcp-client"
    scopes:
      - "openid"
      - "profile"
      - "email"
      - "address"    # Required by Claude
      - "phone"      # Required by Claude
      - "groups"     # Required by Claude
      - "offline_access"
```

## Issue: No redirect back to Claude after login

**Symptom**: User logs into Authelia successfully but stays on the Authelia page instead of redirecting back to Claude.

**Possible Causes**:

1. **Stale consent**: User previously denied consent or consent state is corrupted
   - **Fix**: Log out of Authelia completely, clear browser cookies for the domain, try again

2. **Missing redirect_uris**: The callback URL isn't in the allowed list
   - **Fix**: Ensure these URIs are configured:
     ```yaml
     redirect_uris:
       - "https://claude.ai/api/mcp/auth_callback"
       - "https://api.anthropic.com/oauth/callback"
     ```

3. **CORS issues**: Browser blocking the redirect
   - **Fix**: Ensure CORS is configured:
     ```yaml
     cors:
       endpoints:
         - authorization
         - token
         - revocation
         - introspection
         - userinfo
       allowed_origins_from_client_redirect_uris: true
     ```

## Issue: OIDC issuer URL mismatch

**Symptom**: JWT validation fails in agentgateway with issuer mismatch.

**Cause**: When Authelia is accessed internally (e.g., `http://authelia:9091`), it reports that as the issuer. When accessed via the public URL, it reports the public URL.

**Key insight**: Authelia derives the issuer URL from the request's `Host` header and `X-Forwarded-*` headers. Tailscale Serve correctly forwards these headers, so the public URL works correctly.

**Verification**:
```bash
# Should return the public URL as issuer
curl -s "https://mcp-gateway.YOUR_TAILNET.ts.net/.well-known/openid-configuration" | jq '.issuer'
# Expected: "https://mcp-gateway.YOUR_TAILNET.ts.net"

# Internal access returns internal URL (this is expected)
docker run --rm --network mcp-net curlimages/curl:latest \
  curl -s http://authelia:9091/.well-known/openid-configuration | jq '.issuer'
# Expected: "http://authelia:9091"
```

**Fix**: Ensure agentgateway's issuer config matches the public URL:
```yaml
# agentgateway config.yaml
jwtAuth:
  issuer: "https://mcp-gateway.YOUR_TAILNET.ts.net"
```

## Issue: Encryption key mismatch

**Symptom**: Authelia crashes with "encryption key does not appear to be valid for this database".

**Cause**: The `storage.encryption_key` was changed after the database was created.

**Fix**: Either:
1. Delete the database and let Authelia recreate it (loses all user sessions/consents)
   ```bash
   rm /mnt/user/appdata/authelia/db.sqlite3
   docker restart authelia
   ```
2. Use Authelia CLI to migrate the key (preserves data)
   ```bash
   docker exec authelia authelia crypto storage encryption change-key \
     --new-encryption-key "NEW_KEY"
   ```

## Issue: Redis connection failed

**Symptom**: Authelia can't connect to Redis (`no such host: redis-mcp`).

**Cause**: Authelia container isn't on the same Docker network as Redis.

**Fix**:
```bash
docker network connect mcp-net authelia
docker network connect mcp-net redis-mcp
docker restart authelia
```

## Issue: agentgateway not loading config

**Symptom**: agentgateway starts but returns 502 Bad Gateway or "no route found". Logs don't show the `binds` configuration.

**Cause**: The container wasn't started with the `-f` flag to specify the config file.

**Fix**: Ensure docker-compose.yml includes the command:
```yaml
agentgateway:
  image: ghcr.io/agentgateway/agentgateway:latest
  command: ["-f", "/etc/agentgateway/config.yaml"]
  volumes:
    - /mnt/user/appdata/agentgateway/config.yaml:/etc/agentgateway/config.yaml:ro
```

**Manual fix**:
```bash
docker stop agentgateway && docker rm agentgateway
docker run -d --name agentgateway \
  --network mcp-net \
  -p 8080:8080 \
  -v /mnt/user/appdata/agentgateway/config.yaml:/etc/agentgateway/config.yaml:ro \
  -v /mnt/user/appdata/agentgateway/jwks.json:/etc/agentgateway/jwks.json:ro \
  ghcr.io/agentgateway/agentgateway:latest \
  -f /etc/agentgateway/config.yaml
```

**Verify**: Check logs show "started bind":
```bash
docker logs agentgateway 2>&1 | grep "started bind"
# Expected: info proxy::gateway started bind bind="bind/8080"
```

## Issue: JWT InvalidAudience error

**Symptom**: agentgateway returns 403 with `Error(InvalidAudience)`.

**Cause**: Claude.ai doesn't request an audience parameter during OAuth. Authelia only includes audiences that are explicitly requested by the client. Since Claude doesn't request one, the JWT has no `aud` claim (or an empty one), which fails agentgateway's audience validation.

**Fix**: Use `permissive` mode in agentgateway instead of `strict`:
```yaml
jwtAuth:
  mode: permissive  # validates token but continues on failure
  issuer: "https://mcp-gateway.YOUR_TAILNET.ts.net"
  audiences:
    - "https://mcp-gateway.YOUR_TAILNET.ts.net"
  jwks:
    file: /etc/agentgateway/jwks.json
```

**Security note**: Permissive mode still validates:
- Token signature (via JWKS)
- Issuer claim
- Token expiration

It just doesn't reject requests when audience validation fails.

## Issue: agentgateway config adminAddr format

**Symptom**: agentgateway fails with "config.adminAddr: invalid type: map, expected a string".

**Cause**: The `adminAddr` is in map format instead of string format.

**Wrong**:
```yaml
config:
  adminAddr:
    SocketAddr: "[::]:15000"
```

**Correct**:
```yaml
config:
  adminAddr: "[::]:15000"
```

## Debugging Tips

### Check Authelia logs
```bash
docker logs authelia --tail 50
docker logs authelia -f  # Follow logs in real-time
```

### Test OIDC discovery
```bash
curl -s "https://mcp-gateway.YOUR_TAILNET.ts.net/.well-known/openid-configuration" | jq .
```

### Verify JWKS
```bash
# From Authelia
curl -s "https://mcp-gateway.YOUR_TAILNET.ts.net/jwks.json" | jq '.keys[0].kid'

# In agentgateway
cat /mnt/user/appdata/agentgateway/jwks.json | jq '.keys[0].kid'

# Should match!
```

### Check container networking
```bash
docker network inspect mcp-net
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

# Roadmap Ideas

| Item | Priority | Effort | Notes |
|------|----------|--------|-------|
| ~~JWT Auth in agentgateway~~ | ~~p1~~ | ~~medium~~ | **Done** (2025-12-08) - JWT validation with JWKS from Authelia |
| CEL authorization rules | p2 | medium | Add fine-grained tool-level authorization based on JWT claims |
| ~~CI/CD pipeline for custom Docker apps~~ | ~~p2~~ | ~~large~~ | **Done** (2025-12-08) - Template at `templates/docker-app/` with GHCR, Discord, SSH deploy |
| Enable Authelia OTEL tracing | p3 | small | Add telemetry config to export traces to SigNoz |
| Fix obsidian-mcp health check | p3 | small | Currently failing due to GET request, needs POST-based health check |
| Verify agentgateway traces in SigNoz | p4 | small | Make authenticated request and confirm trace visibility in dashboard |
| Self-hosted GitHub Actions runner | p2 | medium | Deploy runner on Unraid for CI/CD network access |
| Infisical secrets manager | p3 | medium | Self-hosted secrets management with web UI, versioning, audit logs |

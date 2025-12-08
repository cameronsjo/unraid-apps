# Roadmap Ideas

| Item | Priority | Effort | Notes |
|------|----------|--------|-------|
| ~~JWT Auth in agentgateway~~ | ~~p1~~ | ~~medium~~ | **Done** (2025-12-08) - JWT validation with JWKS from Authelia |
| CEL authorization rules | p2 | medium | Add fine-grained tool-level authorization based on JWT claims |
| CI/CD pipeline for custom Docker apps | p2 | large | GitHub Actions with GHCR push, Discord/webhook notification, SSH deploy to Unraid with HITL approval |
| Enable Authelia OTEL tracing | p3 | small | Add telemetry config to export traces to SigNoz |
| Fix obsidian-mcp health check | p3 | small | Currently failing due to GET request, needs POST-based health check |
| Verify agentgateway traces in SigNoz | p4 | small | Make authenticated request and confirm trace visibility in dashboard |

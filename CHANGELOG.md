# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- SigNoz observability stack (traces, metrics, logs)
- agentgateway OTEL export configuration
- Obsidian MCP server integration
- JWT authentication in agentgateway with JWKS from Authelia
- Comprehensive deployment documentation
- CI/CD pipeline template for custom Docker apps (`templates/docker-app/`)
- GHCR authentication on Unraid server

### Changed

- Updated agentgateway config with CORS and JWT policies
- Improved add-mcp.md with correct Obsidian example

## [0.1.0] - 2025-12-07

### Added

- Initial MCP gateway stack
  - Tailscale Funnel for ingress
  - Authelia OIDC provider with TOTP
  - agentgateway MCP proxy
  - Redis session storage
  - mcp-everything test server
- Documentation structure
- git-crypt for secrets management

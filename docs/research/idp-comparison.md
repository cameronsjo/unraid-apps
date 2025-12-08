# Self-Hosted Identity Provider Comparison

> Research Date: 2025-12-07

## Overview

Comparison of self-hosted identity providers for MCP gateway authentication.

## Comparison Matrix

| Feature | Authelia | Logto | Authentik | Keycloak | Ory Hydra |
|---------|----------|-------|-----------|----------|-----------|
| **Primary Focus** | Reverse proxy auth | Modern CIAM/SaaS | Full IdP | Enterprise IAM | Headless OAuth 2.1 |
| **Resource Usage** | ~30MB RAM | Medium | Medium | Heavy (~1GB+) | Light-Medium |
| **OIDC** | Certified (2025) | Full | Full | Full | Certified |
| **OAuth 2.1** | Partial | Yes | Yes | Yes | **Yes (native)** |
| **SAML** | No | Yes | Yes | Yes | No |
| **LDAP/AD** | Yes | Limited | Yes | Yes | No (headless) |
| **Admin UI** | None (YAML) | Modern GUI | Flow-based GUI | Full GUI | None (API) |
| **User Dashboard** | No | Yes | Yes | Yes | BYO |
| **MFA/Passkeys** | TOTP, WebAuthn | Yes | Yes | Yes | BYO |
| **Multi-tenancy** | No | Yes | Yes | Realms | Yes |
| **Docker Image** | 20MB | ~200MB | ~500MB | ~500MB | ~50MB |
| **GitHub Stars** | ~25k | ~11k | ~15k | ~25k | ~16k |

## Detailed Analysis

### Authelia

**Best for:** Homelab, reverse proxy authentication, lightweight deployments

**Pros:**

- Extremely lightweight (~30MB RAM, 20MB Docker image)
- OIDC certified as of 2025
- Passkey/WebAuthn support
- Native LDAP/AD integration
- Simple YAML configuration
- ~25k GitHub stars, active community

**Cons:**

- No admin UI (YAML only)
- No user self-service dashboard
- Not a full IdP (reverse proxy companion)
- No SAML support
- Limited multi-tenancy

**Setup:**

```yaml
# Simple, declarative config
identity_providers:
  oidc:
    clients:
      - client_id: "my-app"
        client_secret: '$argon2id$...'
        redirect_uris:
          - "https://app.example.com/callback"
```

### Logto

**Best for:** Modern SaaS apps, customer-facing applications

**Pros:**

- Developer-first design with clean APIs
- Modern admin UI
- Social login out of the box
- Multi-tenancy support
- OIDC/OAuth 2.0/SAML support
- Free OSS + managed cloud option

**Cons:**

- Redirect-based auth only (no embedded)
- Limited LDAP/AD sync
- Heavier than Authelia
- Less homelab-focused

**Links:**

- Website: https://logto.io/
- GitHub: ~11k stars

### Authentik

**Best for:** SMBs, complex auth flows, visual policy design

**Pros:**

- Visual flow builder for auth journeys
- Clean modern UI
- Redis removed in 2025.10 (simpler stack)
- OIDC + SAML + LDAP
- Good balance of features vs complexity
- ~15k GitHub stars

**Cons:**

- Heavier than Authelia
- Python-based (slower than Go alternatives)
- More complex than needed for simple use cases

**Notable (2025.10):**

> Redis dependency fully removed - caching and WebSocket migrated to Postgres

### Keycloak

**Best for:** Enterprise, Java shops, legacy protocol support

**Pros:**

- Most feature-complete
- Excellent SAML support
- User federation (LDAP, Kerberos, social)
- Fine-grained authorization (UMA 2.0)
- Massive community (~25k stars)
- Red Hat backing

**Cons:**

- Heavy resource usage (~1GB+ RAM)
- Java-based, slower startup
- Complex configuration
- Overkill for homelab

### Ory Hydra

**Best for:** Developers wanting OAuth 2.1 compliance, headless/API-first

**Pros:**

- **Native OAuth 2.1 support**
- OpenID Certified
- Headless (BYO login UI)
- Lightweight (~50MB)
- Used by OpenAI at scale
- Excellent audit trail

**Cons:**

- No built-in user management
- No admin UI
- Requires custom login UI
- Steeper learning curve

**Architecture:**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Your App   │────▶│  Ory Hydra  │────▶│  Your User  │
│             │     │  (OAuth)    │     │  Database   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## MCP Gateway Requirements

For Claude.ai MCP OAuth integration:

| Requirement | RFC | Authelia | Logto | Authentik | Keycloak | Ory Hydra |
|-------------|-----|----------|-------|-----------|----------|-----------|
| OIDC Discovery | - | Yes | Yes | Yes | Yes | Yes |
| PKCE S256 | RFC 7636 | Yes | Yes | Yes | Yes | Yes |
| Dynamic Client Reg | RFC 7591 | No | Partial | Partial | Yes | Yes |
| Protected Resource Metadata | RFC 9728 | No | No | No | No | No |
| Token Introspection | RFC 7662 | Yes | Yes | Yes | Yes | Yes |

**Key insight:** None of the self-hosted IdPs fully implement RFC 9728 (Protected Resource Metadata) yet, which is emerging as important for MCP OAuth flows.

## Recommendation for MCP Gateway

### Current Setup (Authelia)

Authelia works well for the current homelab MCP gateway because:

1. Lightweight - fits Unraid resource constraints
2. OIDC working with Claude.ai
3. TOTP 2FA configured
4. Simple YAML management

**Update (2025-12-08):** JWT validation is now configured in agentgateway. The IdP choice remains appropriate.

### When to Consider Alternatives

**Switch to Logto if:**

- Building customer-facing MCP apps
- Need social login (Google, GitHub)
- Want admin UI for user management
- Planning to scale beyond homelab

**Switch to Authentik if:**

- Need complex auth flows
- Multiple apps with different policies
- Want visual flow designer
- Redis removal (2025.10) appeals

**Switch to Ory Hydra if:**

- Need strict OAuth 2.1 compliance
- Building enterprise-grade system
- Want headless/API-first
- Full audit trail required

**Switch to Keycloak if:**

- Enterprise environment
- Need SAML federation
- Complex user federation (AD/LDAP/Kerberos)
- Have Java expertise

## Sources

- [Authelia vs Authentik Comparison 2025](https://www.houseoffoss.com/post/authelia-vs-authentik-which-self-hosted-identity-provider-is-better-in-2025)
- [State of Open-Source Identity 2025](https://www.houseoffoss.com/post/the-state-of-open-source-identity-in-2025-authentik-vs-authelia-vs-keycloak-vs-zitadel)
- [Top 5 OSS IAM Providers - Logto](https://blog.logto.io/top-oss-iam-providers-2025)
- [Ory Hydra - OAuth 2.1 Provider](https://github.com/ory/hydra)
- [Authentik 2025.10 Release](https://goauthentik.io/blog/2025-10-28-authentik-version-2025-10/)
- [Logto](https://logto.io/)
- [Keycloak](https://www.keycloak.org)
- [Authentik](https://goauthentik.io/)

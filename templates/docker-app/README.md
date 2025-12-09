# Docker App Template for Unraid CI/CD

Template for deploying custom Docker apps to Unraid with GitHub Actions.

## Quick Start

1. Copy this template to your project
2. Customize `Dockerfile` for your app
3. Set up GitHub secrets (see below)
4. Create GitHub environment with approval
5. Tag and push: `git tag v1.0.0 && git push --tags`

## GitHub Secrets

Add these to your repository (Settings > Secrets > Actions):

| Secret | Value |
|--------|-------|
| `UNRAID_HOST` | Unraid Tailscale IP (e.g., `100.x.x.x`) |
| `UNRAID_SSH_KEY` | Private SSH key for root access |
| `DISCORD_WEBHOOK` | Discord webhook URL |
| `TAILSCALE_AUTHKEY` | Tailscale auth key (ephemeral, reusable) |

### Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate new auth key with:
   - **Reusable**: Yes
   - **Ephemeral**: Yes
3. Copy the key (starts with `tskey-auth-`)

## GitHub Environment

1. Go to **Settings > Environments**
2. Create `production` environment
3. Check **Required reviewers**
4. Add yourself as reviewer

## Unraid Setup

```bash
# Create app directory
ssh root@<unraid-ip>
mkdir -p /mnt/user/appdata/<appname>

# Copy docker-compose.prod.yml
scp docker-compose.prod.yml root@<unraid-ip>:/mnt/user/appdata/<appname>/docker-compose.yml
```

## Deploy Flow

```
git tag v1.0.0
    │
    ▼
┌─────────────────┐
│  Build & Push   │──▶ GHCR
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Discord Notify  │──▶ "Ready to deploy"
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ GitHub Approval │◀── Click "Review deployments"
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Tailscale Join  │──▶ Runner joins tailnet
└─────────────────┘
    │
    ▼
┌─────────────────┐
│  SSH Deploy     │──▶ docker compose up -d
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Discord Notify  │──▶ "Deployed successfully"
└─────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `.github/workflows/deploy.yml` | CI/CD pipeline |
| `Dockerfile` | Multi-stage production build |
| `docker-compose.yml` | Local development |
| `docker-compose.prod.yml` | Unraid production |
| `.env.example` | Environment template |

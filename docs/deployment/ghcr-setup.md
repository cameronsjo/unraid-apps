# GitHub Container Registry (GHCR) Setup

Complete setup for pushing images from GitHub Actions and pulling on Unraid.

## GitHub Side

### 1. Enable GHCR (Automatic)

GHCR is enabled by default for all GitHub accounts. No action needed.

### 2. Repository Workflow Permissions

Ensure GitHub Actions can push packages:

1. Go to **Repository > Settings > Actions > General**
2. Scroll to **Workflow permissions**
3. Select **Read and write permissions**
4. Click **Save**

### 3. Package Visibility (Optional)

By default, packages inherit repository visibility. To change:

1. Go to **Your Profile > Packages**
2. Click on the package
3. Click **Package settings**
4. Under **Danger Zone**, change visibility if needed

### 4. Link Package to Repository (Automatic)

The workflow automatically links packages to the repository via labels in the Dockerfile or build metadata.

## Unraid Side

### 1. Create GitHub PAT

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Configure:
   - **Note**: `unraid-ghcr-read`
   - **Expiration**: 90 days or No expiration
   - **Scopes**: Check only `read:packages`
4. Click **Generate token**
5. **Copy the token immediately** (you won't see it again)

### 2. Login to GHCR on Unraid

```bash
ssh root@${UNRAID_IP}

# Replace with your values
GITHUB_USERNAME="your-github-username"
GITHUB_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

# Login
echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
```

Expected output:
```
Login Succeeded
```

### 3. Verify

```bash
# Try pulling a public image first
docker pull ghcr.io/github/super-linter:latest

# Then try your private image (after first push)
docker pull ghcr.io/YOUR_USERNAME/YOUR_APP:latest
```

### 4. Persist Across Reboots

Docker credentials are stored in `/root/.docker/config.json` which persists on Unraid's flash drive. No additional steps needed.

## Workflow Configuration

The deploy workflow already has GHCR configured:

```yaml
# .github/workflows/deploy.yml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    permissions:
      contents: read
      packages: write  # Required for GHCR push

    steps:
      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}  # Automatic, no setup needed
```

**Note:** `GITHUB_TOKEN` is automatically provided by GitHub Actions - no secret to configure.

## Troubleshooting

### "denied: permission_denied" on push

1. Check workflow permissions (Settings > Actions > General)
2. Ensure `packages: write` is in the job permissions

### "unauthorized" on pull (Unraid)

1. Re-login: `docker logout ghcr.io && docker login ghcr.io`
2. Check PAT has `read:packages` scope
3. Check PAT hasn't expired

### Package not visible

1. First push creates the package
2. Check package visibility in GitHub (Profile > Packages)
3. Ensure PAT owner has access to the package

### Image tag not found

```bash
# List available tags
curl -s -H "Authorization: Bearer $(echo -n YOUR_PAT | base64)" \
  https://ghcr.io/v2/YOUR_USERNAME/YOUR_APP/tags/list | jq
```

## Quick Reference

| Task | Command/Location |
|------|------------------|
| Create PAT | https://github.com/settings/tokens |
| Login on Unraid | `docker login ghcr.io -u USER --password-stdin` |
| Check login | `docker login ghcr.io --get-login` |
| Logout | `docker logout ghcr.io` |
| Pull image | `docker pull ghcr.io/USER/APP:TAG` |
| List local images | `docker images ghcr.io/*` |

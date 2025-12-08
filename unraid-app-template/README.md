# Unraid App Template

Deploy custom Docker applications to Unraid with CI/CD and human-in-the-loop (HITL) approval.

## Features

- **Tag-triggered deployments**: Push a version tag to trigger the pipeline
- **HITL approval**: Discord notification with approval gate before deployment
- **GHCR integration**: Images stored in GitHub Container Registry
- **Tailscale SSH**: Secure deployment without managing SSH keys
- **Optional native GUI**: Unraid Docker tab integration via XML templates

## Deployment Patterns

This template supports two deployment patterns:

| Pattern | Use Case | Documentation |
|---------|----------|---------------|
| **Standalone** | Simple apps, direct Docker deployment | This README |
| **Gateway** | MCP servers with OAuth, multi-app routing | [gateway/README.md](gateway/README.md) |

## Architecture (Standalone)

```
git tag v1.0.0 && git push --tags
           │
           ▼
┌─────────────────────────────────────────┐
│         GitHub Actions Workflow          │
│                                          │
│  Build ──▶ Push GHCR ──▶ Discord Notify │
│                              │           │
│                    [HITL Approval Gate]  │
│                              │           │
│                              ▼           │
│                     Tailscale SSH Deploy │
└─────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────┐
│            Unraid Server                 │
│  /mnt/user/appdata/myapp/               │
│    ├── docker-compose.yml               │
│    ├── .env                              │
│    └── data/                             │
└─────────────────────────────────────────┘
```

## Quick Start

### 1. Use This Template

```bash
git clone https://github.com/YOUR_USERNAME/unraid-app-template.git myapp
cd myapp
rm -rf .git
git init
git remote add origin https://github.com/YOUR_USERNAME/myapp.git
```

### 2. Configure GitHub Secrets

Run the setup script (requires `gh` CLI):

```bash
./scripts/setup-github.sh
```

Or manually add secrets in **Settings > Secrets and variables > Actions**:

| Secret                          | Description                                    |
| ------------------------------- | ---------------------------------------------- |
| `TAILSCALE_OAUTH_CLIENT_ID`     | Tailscale OAuth client ID                      |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | Tailscale OAuth client secret                  |
| `UNRAID_TAILSCALE_HOSTNAME`     | Unraid Tailscale hostname (e.g., `tower`)      |
| `DISCORD_WEBHOOK_URL`           | Discord webhook URL                            |

**No SSH keys required!** Tailscale SSH handles authentication.

### 3. Create GitHub Environment

Go to **Settings > Environments** and create `production`:

1. Click **New environment** > Name: `production`
2. Check **Required reviewers** and add yourself
3. (Optional) Add deployment branch rule: `v*`

### 4. Set Up Tailscale SSH

1. **Enable Tailscale SSH on Unraid**:
   - Unraid WebUI > Settings > Tailscale
   - Enable "Tailscale SSH"

2. **Configure Tailscale ACL** at https://login.tailscale.com/admin/acls:
   ```json
   {
     "tagOwners": {
       "tag:ci": ["autogroup:admin"],
       "tag:server": ["autogroup:admin"]
     },
     "acls": [
       {"action": "accept", "src": ["tag:ci"], "dst": ["tag:server:*"]}
     ],
     "ssh": [
       {
         "action": "accept",
         "src": ["tag:ci"],
         "dst": ["tag:server"],
         "users": ["root"]
       }
     ]
   }
   ```

3. **Tag your Unraid server** as `server` in Tailscale admin

### 5. Set Up Unraid Server

```bash
# Via Tailscale SSH (after setup above)
tailscale ssh root@tower

# Or via local network during initial setup
ssh root@<unraid-ip>

# Run setup script
bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/myapp/main/scripts/setup-unraid.sh) \
  --app myapp \
  --github-user YOUR_USERNAME
```

### 6. Deploy

```bash
git add .
git commit -m "feat: initial commit"
git tag v1.0.0
git push && git push --tags
```

The workflow will:

1. Build the Docker image
2. Push to GHCR
3. Send Discord notification
4. Wait for your approval in GitHub
5. Deploy to Unraid via Tailscale SSH

## File Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD workflow
├── gateway/                    # MCP Gateway pattern (see gateway/README.md)
│   ├── docker-compose.yml
│   ├── authelia/
│   ├── agentgateway.yaml
│   └── ...
├── scripts/
│   ├── setup-github.sh         # Configure GitHub via gh CLI
│   ├── setup-unraid.sh         # Unraid server setup
│   └── create-template.sh      # Generate Unraid XML template
├── Dockerfile                  # Multi-stage production build
├── docker-compose.yml          # Local development
├── docker-compose.prod.yml     # Unraid production
├── unraid-template.xml         # Native Unraid GUI template
├── .env.example                # Environment template
└── README.md
```

## Local Development

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your settings
vim .env

# Start locally
docker compose up --build
```

## Customization

### Dockerfile

The template uses Node.js. Modify for your stack:

```dockerfile
# Python example
FROM python:3.12-slim AS production
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0"]
```

### Ports

Update in all files:

- `Dockerfile`: `EXPOSE` directive
- `docker-compose.yml`: `ports` mapping
- `docker-compose.prod.yml`: `ports` mapping
- `unraid-template.xml`: Port config

### Additional Volumes

Add to `docker-compose.prod.yml`:

```yaml
volumes:
  - /mnt/user/appdata/myapp/data:/app/data
  - /mnt/user/appdata/myapp/config:/app/config
  - /mnt/user/media:/media:ro  # Read-only media access
```

## Native Unraid GUI Integration (Optional)

For containers to appear in Unraid's Docker tab:

```bash
# SSH to Unraid
tailscale ssh root@tower

# Run template generator
bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/myapp/main/scripts/create-template.sh) \
  --app myapp \
  --github-user YOUR_USERNAME \
  --port 3000
```

The app will appear in **Apps > private** section.

## Troubleshooting

### Tailscale SSH Connection Failed

```bash
# Check Tailscale status
tailscale status

# Verify ACL allows tag:ci to SSH to tag:server
# Check Unraid has Tailscale SSH enabled
```

### GHCR Pull Failed

```bash
# Re-authenticate on Unraid
docker logout ghcr.io
docker login ghcr.io -u YOUR_USERNAME
# Use a PAT with read:packages scope
```

### Container Not Starting

```bash
# SSH to Unraid and check logs
tailscale ssh root@tower
cd /mnt/user/appdata/myapp
docker compose logs -f
```

### Workflow Waiting for Approval

1. Check **Settings > Environments > production** has required reviewers
2. Look for the approval request in **Actions** tab
3. Click **Review deployments** > **Approve**

## Discord Webhook Setup

1. Open your Discord server
2. Go to **Server Settings > Integrations > Webhooks**
3. Click **New Webhook**
4. Name it (e.g., "GitHub Deployments")
5. Select the channel for notifications
6. Click **Copy Webhook URL**
7. Add to GitHub Secrets as `DISCORD_WEBHOOK_URL`

## Security Considerations

- **No SSH keys to manage** - Tailscale SSH uses your Tailscale identity
- **Ephemeral nodes** - GitHub Actions runner joins Tailscale, deploys, then disappears
- **ACL-controlled** - Tailscale ACLs restrict what `tag:ci` can access
- **Not exposed to internet** - Unraid only accessible via Tailscale
- GitHub Environments with required reviewers add HITL approval
- Secrets are encrypted at rest in GitHub

## License

MIT

#!/usr/bin/env bash
# =============================================================================
# GitHub Repository Setup Script
# =============================================================================
# Configures GitHub secrets and environment for Unraid deployment via Tailscale SSH.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - Tailscale account with OAuth client created
#   - Tailscale SSH enabled on Unraid
#   - Discord webhook URL
#
# Usage:
#   ./scripts/setup-github.sh
#
# Or with arguments:
#   ./scripts/setup-github.sh --repo owner/repo --unraid-hostname tower
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
prompt() { echo -e "${CYAN}[?]${NC} $*"; }

# Default values
REPO=""
UNRAID_HOSTNAME=""
DISCORD_WEBHOOK=""
TAILSCALE_CLIENT_ID=""
TAILSCALE_CLIENT_SECRET=""

# Usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configure GitHub repository for Unraid CI/CD deployment via Tailscale SSH.

Options:
    --repo OWNER/REPO         GitHub repository (default: current repo)
    --unraid-hostname NAME    Unraid Tailscale hostname (e.g., "tower" or "unraid")
    --discord-webhook URL     Discord webhook URL
    --tailscale-id ID         Tailscale OAuth client ID
    --tailscale-secret SECRET Tailscale OAuth client secret
    --help                    Show this help message

Example:
    $(basename "$0") --repo myuser/myapp --unraid-hostname tower

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo) REPO="$2"; shift 2 ;;
        --unraid-hostname) UNRAID_HOSTNAME="$2"; shift 2 ;;
        --discord-webhook) DISCORD_WEBHOOK="$2"; shift 2 ;;
        --tailscale-id) TAILSCALE_CLIENT_ID="$2"; shift 2 ;;
        --tailscale-secret) TAILSCALE_CLIENT_SECRET="$2"; shift 2 ;;
        --help) usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

# Check gh CLI
if ! command -v gh &> /dev/null; then
    error "gh CLI not found. Install from: https://cli.github.com/"
    exit 1
fi

# Check gh auth
if ! gh auth status &> /dev/null; then
    error "Not authenticated with gh. Run: gh auth login"
    exit 1
fi

# Get current repo if not specified
if [[ -z "$REPO" ]]; then
    if git rev-parse --git-dir &> /dev/null; then
        REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    fi
    if [[ -z "$REPO" ]]; then
        error "Could not detect repository. Use --repo owner/repo"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "  GitHub Repository Setup"
echo "=========================================="
echo ""
info "Repository: ${REPO}"
echo ""

# =============================================================================
# Collect missing values interactively
# =============================================================================

# Tailscale OAuth Client ID
if [[ -z "$TAILSCALE_CLIENT_ID" ]]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  TAILSCALE OAUTH SETUP                                          │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    echo "│  1. Go to: https://login.tailscale.com/admin/settings/oauth    │"
    echo "│  2. Click 'Generate OAuth Client'                               │"
    echo "│  3. Description: 'GitHub Actions CI/CD'                         │"
    echo "│  4. Scopes: Check 'Devices - Write' and 'Auth Keys - Write'    │"
    echo "│  5. Tags: Add 'tag:ci'                                          │"
    echo "│  6. Click 'Generate'                                            │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    prompt "Tailscale OAuth Client ID:"
    read -rp "> " TAILSCALE_CLIENT_ID
fi

# Tailscale OAuth Client Secret
if [[ -z "$TAILSCALE_CLIENT_SECRET" ]]; then
    prompt "Tailscale OAuth Client Secret:"
    read -rsp "> " TAILSCALE_CLIENT_SECRET
    echo ""
fi

# Unraid Tailscale Hostname
if [[ -z "$UNRAID_HOSTNAME" ]]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  UNRAID TAILSCALE HOSTNAME                                      │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    echo "│  Find this in Tailscale admin console or run on Unraid:        │"
    echo "│    tailscale status                                             │"
    echo "│                                                                  │"
    echo "│  Usually something like 'tower' or 'unraid'                     │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    prompt "Unraid Tailscale hostname:"
    read -rp "> " UNRAID_HOSTNAME
fi

# Discord Webhook
if [[ -z "$DISCORD_WEBHOOK" ]]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  DISCORD WEBHOOK SETUP                                          │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    echo "│  1. Open Discord server settings                                │"
    echo "│  2. Go to: Integrations > Webhooks                              │"
    echo "│  3. Click 'New Webhook'                                         │"
    echo "│  4. Name it 'GitHub Deployments'                                │"
    echo "│  5. Select channel for notifications                            │"
    echo "│  6. Click 'Copy Webhook URL'                                    │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    prompt "Discord Webhook URL:"
    read -rp "> " DISCORD_WEBHOOK
fi

# =============================================================================
# Set GitHub Secrets
# =============================================================================

echo ""
info "Setting GitHub secrets..."

# Tailscale
echo "$TAILSCALE_CLIENT_ID" | gh secret set TAILSCALE_OAUTH_CLIENT_ID --repo "$REPO"
success "Set TAILSCALE_OAUTH_CLIENT_ID"

echo "$TAILSCALE_CLIENT_SECRET" | gh secret set TAILSCALE_OAUTH_CLIENT_SECRET --repo "$REPO"
success "Set TAILSCALE_OAUTH_CLIENT_SECRET"

# Unraid
echo "$UNRAID_HOSTNAME" | gh secret set UNRAID_TAILSCALE_HOSTNAME --repo "$REPO"
success "Set UNRAID_TAILSCALE_HOSTNAME"

# Discord
echo "$DISCORD_WEBHOOK" | gh secret set DISCORD_WEBHOOK_URL --repo "$REPO"
success "Set DISCORD_WEBHOOK_URL"

# =============================================================================
# Create GitHub Environment
# =============================================================================

echo ""
info "Creating 'production' environment with required reviewers..."

# Get user ID for reviewer
USER_ID=$(gh api user -q .id)

# Create environment with required reviewers
gh api \
    --method PUT \
    "/repos/${REPO}/environments/production" \
    --input - << EOF 2>/dev/null || warn "Environment may need manual configuration"
{
  "reviewers": [
    {
      "type": "User",
      "id": ${USER_ID}
    }
  ],
  "deployment_branch_policy": null
}
EOF

success "Created 'production' environment"

# =============================================================================
# Verify Setup
# =============================================================================

echo ""
info "Verifying secrets..."

SECRETS=$(gh secret list --repo "$REPO" --json name -q '.[].name' | tr '\n' ' ')
REQUIRED_SECRETS="TAILSCALE_OAUTH_CLIENT_ID TAILSCALE_OAUTH_CLIENT_SECRET UNRAID_TAILSCALE_HOSTNAME DISCORD_WEBHOOK_URL"

ALL_SET=true
for secret in $REQUIRED_SECRETS; do
    if echo "$SECRETS" | grep -q "$secret"; then
        success "$secret"
    else
        error "$secret not found"
        ALL_SET=false
    fi
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""

if [[ "$ALL_SET" == "true" ]]; then
    success "All secrets configured"
else
    warn "Some secrets may need manual configuration"
fi

echo ""
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  REMAINING STEPS                                                 │"
echo "├─────────────────────────────────────────────────────────────────┤"
echo "│                                                                  │"
echo "│  1. ENABLE TAILSCALE SSH ON UNRAID                              │"
echo "│     - Unraid WebUI > Settings > Tailscale                       │"
echo "│     - Enable 'Tailscale SSH'                                    │"
echo "│                                                                  │"
echo "│  2. CONFIGURE TAILSCALE ACL                                     │"
echo "│     Go to: https://login.tailscale.com/admin/acls               │"
echo "│                                                                  │"
echo "│     Add to tagOwners:                                           │"
echo "│       \"tag:ci\": [\"autogroup:admin\"],                           │"
echo "│       \"tag:server\": [\"autogroup:admin\"]                         │"
echo "│                                                                  │"
echo "│     Add to acls:                                                │"
echo "│       {                                                          │"
echo "│         \"action\": \"accept\",                                    │"
echo "│         \"src\": [\"tag:ci\"],                                      │"
echo "│         \"dst\": [\"tag:server:*\"]                                 │"
echo "│       }                                                          │"
echo "│                                                                  │"
echo "│     Add to ssh section:                                         │"
echo "│       {                                                          │"
echo "│         \"action\": \"accept\",                                    │"
echo "│         \"src\": [\"tag:ci\"],                                      │"
echo "│         \"dst\": [\"tag:server\"],                                  │"
echo "│         \"users\": [\"root\"]                                       │"
echo "│       }                                                          │"
echo "│                                                                  │"
echo "│  3. TAG YOUR UNRAID SERVER                                      │"
echo "│     - Tailscale admin > Machines > Your Unraid                  │"
echo "│     - Add tag: 'server'                                         │"
echo "│                                                                  │"
echo "│  4. TEST DEPLOYMENT                                             │"
echo "│     git tag v0.0.1-test && git push --tags                      │"
echo "│                                                                  │"
echo "└─────────────────────────────────────────────────────────────────┘"
echo ""
success "Ready for deployments!"

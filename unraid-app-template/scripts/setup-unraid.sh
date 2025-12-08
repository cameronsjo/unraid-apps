#!/usr/bin/env bash
# =============================================================================
# Unraid Server Setup Script
# =============================================================================
# Run this script on your Unraid server to prepare for deployments.
#
# Usage:
#   SSH to Unraid: ssh root@<unraid-ip>
#   Run: curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/scripts/setup-unraid.sh | bash
#
#   Or manually:
#   bash setup-unraid.sh --app myapp --github-user YOUR_USERNAME
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
APP_NAME=""
GITHUB_USERNAME=""
GITHUB_PAT=""
APPDATA_BASE="/mnt/user/appdata"

# Print functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --app NAME          Application name (required)
    --github-user USER  GitHub username (required for GHCR auth)
    --github-pat PAT    GitHub Personal Access Token (will prompt if not provided)
    --help              Show this help message

Example:
    $(basename "$0") --app myapp --github-user cameronsjo

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --app)
            APP_NAME="$2"
            shift 2
            ;;
        --github-user)
            GITHUB_USERNAME="$2"
            shift 2
            ;;
        --github-pat)
            GITHUB_PAT="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$APP_NAME" ]]; then
    error "Application name is required (--app)"
    usage
fi

if [[ -z "$GITHUB_USERNAME" ]]; then
    error "GitHub username is required (--github-user)"
    usage
fi

# Prompt for PAT if not provided
if [[ -z "$GITHUB_PAT" ]]; then
    echo ""
    info "GitHub Personal Access Token required for GHCR authentication."
    info "Create one at: https://github.com/settings/tokens"
    info "Required scope: read:packages"
    echo ""
    read -sp "Enter GitHub PAT: " GITHUB_PAT
    echo ""
fi

echo ""
echo "=========================================="
echo "  Unraid Setup for: ${APP_NAME}"
echo "=========================================="
echo ""

# Step 1: Create app directory
info "Creating app directory..."
APP_DIR="${APPDATA_BASE}/${APP_NAME}"
mkdir -p "${APP_DIR}/data"
success "Created ${APP_DIR}"

# Step 2: Authenticate with GHCR
info "Authenticating with GitHub Container Registry..."
echo "${GITHUB_PAT}" | docker login ghcr.io -u "${GITHUB_USERNAME}" --password-stdin
success "Authenticated with GHCR"

# Step 3: Create docker-compose.yml if it doesn't exist
if [[ ! -f "${APP_DIR}/docker-compose.yml" ]]; then
    info "Creating docker-compose.yml..."
    cat > "${APP_DIR}/docker-compose.yml" << EOF
# Production docker-compose for ${APP_NAME}
# Managed by GitHub Actions CI/CD

services:
  app:
    image: ghcr.io/${GITHUB_USERNAME}/${APP_NAME}:\${VERSION:-latest}
    container_name: ${APP_NAME}
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ${APP_DIR}/data:/app/data
    environment:
      - NODE_ENV=production
      - TZ=America/Chicago
    env_file:
      - .env
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF
    success "Created docker-compose.yml"
else
    warn "docker-compose.yml already exists, skipping"
fi

# Step 4: Create .env file
if [[ ! -f "${APP_DIR}/.env" ]]; then
    info "Creating .env file..."
    cat > "${APP_DIR}/.env" << EOF
# Environment configuration for ${APP_NAME}
# Updated automatically by CI/CD pipeline

VERSION=latest
APP_NAME=${APP_NAME}
GITHUB_USERNAME=${GITHUB_USERNAME}
TZ=America/Chicago

# Add your app-specific environment variables below:
# DATABASE_URL=
# API_KEY=
EOF
    success "Created .env file"
else
    warn ".env already exists, skipping"
fi

# Step 5: Create initial data directory structure
info "Setting up data directory..."
mkdir -p "${APP_DIR}/data"
success "Data directory ready"

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
info "App directory: ${APP_DIR}"
info "Docker compose: ${APP_DIR}/docker-compose.yml"
info "Environment: ${APP_DIR}/.env"
echo ""
info "Next steps:"
echo "  1. Add UNRAID_HOST, UNRAID_SSH_KEY, SLACK_WEBHOOK_URL to GitHub secrets"
echo "  2. Create 'production' environment in GitHub with required reviewers"
echo "  3. Push a tag to trigger deployment: git tag v1.0.0 && git push --tags"
echo ""
success "Ready for deployments!"

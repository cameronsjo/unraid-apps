#!/usr/bin/env bash
# =============================================================================
# Generate Unraid Community Applications XML Template
# =============================================================================
# Creates an XML template for native Unraid Docker GUI integration.
# The template will appear in Apps > "private" section.
#
# Usage:
#   ./create-template.sh --app myapp --github-user YOUR_USERNAME --port 3000
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Defaults
APP_NAME=""
GITHUB_USERNAME=""
PORT="3000"
DESCRIPTION="Custom application deployed via CI/CD"
CATEGORY="Tools:"
ICON_URL=""
TEMPLATE_DIR="/boot/config/plugins/community.applications/private"

# Usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate an Unraid XML template for native Docker GUI integration.

Options:
    --app NAME          Application name (required)
    --github-user USER  GitHub username (required)
    --port PORT         Application port (default: 3000)
    --description DESC  Application description
    --category CAT      Unraid category (default: Tools:)
    --icon URL          Icon URL (optional)
    --output DIR        Output directory (default: Unraid private templates)
    --help              Show this help message

Example:
    $(basename "$0") --app myapp --github-user cameronsjo --port 8080

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
        --port)
            PORT="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --icon)
            ICON_URL="$2"
            shift 2
            ;;
        --output)
            TEMPLATE_DIR="$2"
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

# Validate
if [[ -z "$APP_NAME" ]]; then
    error "Application name is required (--app)"
    usage
fi

if [[ -z "$GITHUB_USERNAME" ]]; then
    error "GitHub username is required (--github-user)"
    usage
fi

# Set defaults
if [[ -z "$ICON_URL" ]]; then
    ICON_URL="https://raw.githubusercontent.com/${GITHUB_USERNAME}/${APP_NAME}/main/icon.png"
fi

# Create template directory
TEMPLATE_PATH="${TEMPLATE_DIR}/${APP_NAME}"
mkdir -p "${TEMPLATE_PATH}"

# Generate XML template
TEMPLATE_FILE="${TEMPLATE_PATH}/${APP_NAME}.xml"

info "Generating Unraid template for ${APP_NAME}..."

cat > "${TEMPLATE_FILE}" << EOF
<?xml version="1.0"?>
<Container version="2">
  <Name>${APP_NAME}</Name>
  <Repository>ghcr.io/${GITHUB_USERNAME}/${APP_NAME}:latest</Repository>
  <Registry>https://ghcr.io/</Registry>
  <Network>bridge</Network>
  <MyIP/>
  <Shell>bash</Shell>
  <Privileged>false</Privileged>
  <Support/>
  <Project>https://github.com/${GITHUB_USERNAME}/${APP_NAME}</Project>
  <Overview>${DESCRIPTION}</Overview>
  <Category>${CATEGORY}</Category>
  <WebUI>http://[IP]:[PORT:${PORT}]/</WebUI>
  <TemplateURL/>
  <Icon>${ICON_URL}</Icon>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DateInstalled></DateInstalled>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name="Web Port" Target="${PORT}" Default="${PORT}" Mode="tcp" Description="Web interface port" Type="Port" Display="always" Required="true" Mask="false">${PORT}</Config>
  <Config Name="Data Directory" Target="/app/data" Default="/mnt/user/appdata/${APP_NAME}/data" Mode="rw" Description="Persistent data directory" Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/${APP_NAME}/data</Config>
  <Config Name="Timezone" Target="TZ" Default="America/Chicago" Mode="" Description="Container timezone" Type="Variable" Display="always" Required="false" Mask="false">America/Chicago</Config>
  <Config Name="PUID" Target="PUID" Default="99" Mode="" Description="User ID for file permissions" Type="Variable" Display="advanced" Required="false" Mask="false">99</Config>
  <Config Name="PGID" Target="PGID" Default="100" Mode="" Description="Group ID for file permissions" Type="Variable" Display="advanced" Required="false" Mask="false">100</Config>
</Container>
EOF

success "Template created: ${TEMPLATE_FILE}"

echo ""
echo "=========================================="
echo "  Unraid Template Generated"
echo "=========================================="
echo ""
info "Template location: ${TEMPLATE_FILE}"
info "The app will appear in: Apps > private"
echo ""
info "To use the template:"
echo "  1. Go to Unraid WebGUI > Apps"
echo "  2. Look for 'private' section or search for '${APP_NAME}'"
echo "  3. Click to install - settings will be pre-configured"
echo ""
warn "Note: This template uses :latest tag. For version control,"
warn "manually update the tag or use docker-compose deployment instead."
echo ""

# Also output to stdout for easy copy
if [[ "$TEMPLATE_DIR" != "/boot/config/plugins/community.applications/private" ]]; then
    echo "Generated template content:"
    echo "---"
    cat "${TEMPLATE_FILE}"
fi

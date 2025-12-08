#!/usr/bin/env bash
# =============================================================================
# Generate Secrets for MCP Gateway
# =============================================================================
# Creates all required secrets for Authelia OIDC configuration.
#
# Usage:
#   ./scripts/generate-secrets.sh
#
# This will:
#   1. Generate HMAC secret for JWT signing
#   2. Generate RSA key for OIDC
#   3. Prompt for user password and generate hash
#   4. Generate OIDC client secret and hash
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

# Find gateway directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="${SCRIPT_DIR}/../gateway"
SECRETS_DIR="${GATEWAY_DIR}/authelia/secrets"

# Check if we're in the right place
if [[ ! -d "${GATEWAY_DIR}" ]]; then
    error "Gateway directory not found at ${GATEWAY_DIR}"
    exit 1
fi

echo ""
echo "=========================================="
echo "  MCP Gateway Secret Generation"
echo "=========================================="
echo ""

# Create secrets directory
mkdir -p "${SECRETS_DIR}"
info "Secrets directory: ${SECRETS_DIR}"
echo ""

# =============================================================================
# 1. HMAC Secret
# =============================================================================
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  1. HMAC SECRET (JWT Signing)                                   │"
echo "└─────────────────────────────────────────────────────────────────┘"

HMAC_FILE="${SECRETS_DIR}/hmac"
if [[ -f "${HMAC_FILE}" ]]; then
    warn "HMAC secret already exists. Overwrite? (y/N)"
    read -r response
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        info "Keeping existing HMAC secret"
    else
        openssl rand -hex 64 > "${HMAC_FILE}"
        success "Generated new HMAC secret"
    fi
else
    openssl rand -hex 64 > "${HMAC_FILE}"
    success "Generated HMAC secret"
fi
echo ""

# =============================================================================
# 2. RSA Key for OIDC
# =============================================================================
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  2. RSA KEY (OIDC Signing)                                      │"
echo "└─────────────────────────────────────────────────────────────────┘"

RSA_FILE="${SECRETS_DIR}/issuer.pem"
if [[ -f "${RSA_FILE}" ]]; then
    warn "RSA key already exists. Overwrite? (y/N)"
    read -r response
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        info "Keeping existing RSA key"
    else
        openssl genrsa -out "${RSA_FILE}" 4096 2>/dev/null
        success "Generated new RSA key (4096 bit)"
    fi
else
    openssl genrsa -out "${RSA_FILE}" 4096 2>/dev/null
    success "Generated RSA key (4096 bit)"
fi
echo ""

# =============================================================================
# 3. User Password Hash
# =============================================================================
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  3. USER PASSWORD HASH                                          │"
echo "└─────────────────────────────────────────────────────────────────┘"

prompt "Enter password for Authelia user:"
read -rs USER_PASSWORD
echo ""

if [[ -n "${USER_PASSWORD}" ]]; then
    info "Generating Argon2 hash (this may take a moment)..."

    USER_HASH=$(docker run --rm authelia/authelia:latest \
        crypto hash generate argon2 --password "${USER_PASSWORD}" 2>/dev/null | grep '^\$argon2')

    if [[ -n "${USER_HASH}" ]]; then
        success "Password hash generated"
        echo ""
        echo "Add this to gateway/authelia/users.yml:"
        echo ""
        echo -e "${CYAN}password: \"${USER_HASH}\"${NC}"
        echo ""
    else
        error "Failed to generate password hash"
    fi
else
    warn "Skipped password hash generation"
fi
echo ""

# =============================================================================
# 4. OIDC Client Secret
# =============================================================================
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  4. OIDC CLIENT SECRET                                          │"
echo "└─────────────────────────────────────────────────────────────────┘"

# Generate random client secret
CLIENT_SECRET=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
info "Generated client secret (plaintext - save this!):"
echo ""
echo -e "${CYAN}${CLIENT_SECRET}${NC}"
echo ""

info "Generating PBKDF2 hash for Authelia..."
CLIENT_HASH=$(docker run --rm authelia/authelia:latest \
    crypto hash generate pbkdf2 --password "${CLIENT_SECRET}" 2>/dev/null | grep '^\$pbkdf2')

if [[ -n "${CLIENT_HASH}" ]]; then
    success "Client secret hash generated"
    echo ""
    echo "Add this to gateway/authelia/configuration.yml (client_secret field):"
    echo ""
    echo -e "${CYAN}client_secret: '${CLIENT_HASH}'${NC}"
    echo ""

    echo "Add the PLAINTEXT secret to gateway/.env:"
    echo ""
    echo -e "${CYAN}OIDC_CLIENT_SECRET=${CLIENT_SECRET}${NC}"
    echo ""
else
    error "Failed to generate client secret hash"
fi

# =============================================================================
# 5. Session Secret
# =============================================================================
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  5. SESSION SECRET                                              │"
echo "└─────────────────────────────────────────────────────────────────┘"

SESSION_SECRET=$(openssl rand -hex 32)
info "Generated session secret:"
echo ""
echo "Add this to gateway/.env:"
echo ""
echo -e "${CYAN}AUTHELIA_SESSION_SECRET=${SESSION_SECRET}${NC}"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=========================================="
echo "  Secret Generation Complete"
echo "=========================================="
echo ""
success "Generated files:"
echo "  - ${SECRETS_DIR}/hmac"
echo "  - ${SECRETS_DIR}/issuer.pem"
echo ""
warn "Manual steps remaining:"
echo "  1. Add password hash to gateway/authelia/users.yml"
echo "  2. Add client_secret hash to gateway/authelia/configuration.yml"
echo "  3. Add plaintext secrets to gateway/.env:"
echo "     - OIDC_CLIENT_SECRET"
echo "     - AUTHELIA_SESSION_SECRET"
echo "  4. Replace YOUR_TAILNET in all config files"
echo ""
success "Ready to deploy!"

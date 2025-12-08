#!/bin/bash
# Generate a GPG key for git-crypt
# Edit the values below before running

# --- EDIT THESE ---
NAME_REAL="Your Name"
NAME_EMAIL="your-email@example.com"
KEY_LENGTH=4096  # 4096 is recommended; 2048 is minimum acceptable
EXPIRE_DATE=0    # 0 = never expires, or use "2y" for 2 years
# ------------------

set -e

echo "Generating GPG key for: $NAME_REAL <$NAME_EMAIL>"
echo "Key length: $KEY_LENGTH bits"
echo "Expiration: ${EXPIRE_DATE:-never}"
echo ""

# Create temp params file
PARAMS_FILE=$(mktemp)
cat > "$PARAMS_FILE" << EOF
%echo Generating a GPG key for git-crypt
Key-Type: RSA
Key-Length: $KEY_LENGTH
Subkey-Type: RSA
Subkey-Length: $KEY_LENGTH
Name-Real: $NAME_REAL
Name-Email: $NAME_EMAIL
Expire-Date: $EXPIRE_DATE
%no-protection
%commit
%echo Done
EOF

# Generate the key
gpg --batch --generate-key "$PARAMS_FILE"

# Clean up
rm -f "$PARAMS_FILE"

# Get the key ID
KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "$NAME_EMAIL" 2>/dev/null | grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)

echo ""
echo "=== GPG Key Generated ==="
echo "Key ID: $KEY_ID"
echo ""
echo "To export private key for backup (store in 1Password):"
echo "  gpg --armor --export-secret-keys $NAME_EMAIL > gpg-private-key.asc"
echo ""
echo "To add to git-crypt:"
echo "  git-crypt add-gpg-user --trusted $NAME_EMAIL"
echo ""
echo "To verify:"
echo "  gpg --list-secret-keys $NAME_EMAIL"

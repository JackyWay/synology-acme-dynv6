#!/bin/bash

################################################################################
# Native acme.sh Installation Script for Synology DSM
#
# This script installs acme.sh natively on DSM for certificate deployment.
# The Docker container will still handle certificate issuance/renewal.
#
# Usage: sudo ./install-acme-native.sh
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Installation paths
ACME_INSTALL_DIR="/usr/local/share/acme.sh"
ACME_DATA_DIR="$PROJECT_DIR/acme-data"

echo -e "${BLUE}=== Native acme.sh Installation for Synology DSM ===${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

echo -e "${YELLOW}This script will:${NC}"
echo "1. Download and install acme.sh to $ACME_INSTALL_DIR"
echo "2. Extract and install the native acme.sh"
echo "3. Configure it to use the shared certificate directory: $ACME_DATA_DIR"
echo "4. Create symlinks for easy access"
echo "5. Set proper permissions"
echo "6. Verify the installation"
echo ""
echo -e "${YELLOW}Note: Docker container will continue to handle certificate issuance/renewal.${NC}"
echo -e "${YELLOW}      Native acme.sh will ONLY be used for DSM deployment.${NC}"
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Create installation directory
echo -e "${BLUE}[1/6] Creating installation directory...${NC}"
mkdir -p "$ACME_INSTALL_DIR"

# Download acme.sh
echo -e "${BLUE}[2/6] Downloading acme.sh...${NC}"

cd /tmp
rm -rf acme.sh-master acme.sh.tar.gz 2>/dev/null || true

# Download from GitHub
if command -v wget >/dev/null 2>&1; then
    wget -O acme.sh.tar.gz https://github.com/acmesh-official/acme.sh/archive/master.tar.gz
elif command -v curl >/dev/null 2>&1; then
    curl -L -o acme.sh.tar.gz https://github.com/acmesh-official/acme.sh/archive/master.tar.gz
else
    echo -e "${RED}Error: Neither wget nor curl is available${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Downloaded acme.sh${NC}"

# Extract and install
echo -e "${BLUE}[3/6] Extracting and installing...${NC}"
tar -xzf acme.sh.tar.gz
cd acme.sh-master

# Run installer with proper paths
./acme.sh --install \
    --home "$ACME_INSTALL_DIR" \
    --config-home "$ACME_DATA_DIR" \
    --cert-home "$ACME_DATA_DIR" \
    --no-cron \
    --no-profile

# Clean up
cd /tmp
rm -rf acme.sh-master acme.sh.tar.gz

echo -e "${GREEN}✓ acme.sh installed${NC}"

# Configure acme.sh to use shared certificate directory
echo -e "${BLUE}[4/6] Configuring acme.sh...${NC}"

# Create config directory if it doesn't exist
mkdir -p "$ACME_DATA_DIR"

# Create or update account.conf
if [ ! -f "$ACME_DATA_DIR/account.conf" ]; then
    cat > "$ACME_DATA_DIR/account.conf" << EOF
# acme.sh configuration
# This file is shared between Docker and native installations

ACCOUNT_CONF_PATH='$ACME_DATA_DIR/account.conf'
CERT_HOME='$ACME_DATA_DIR'
ACCOUNT_KEY_PATH='$ACME_DATA_DIR/account.key'

# Log settings
LOG_FILE='$PROJECT_DIR/logs/acme-native.log'
LOG_LEVEL=1

# Auto-upgrade (disable to prevent conflicts with Docker)
AUTO_UPGRADE=0
EOF
    echo -e "${GREEN}✓ Created account.conf${NC}"
else
    echo -e "${YELLOW}✓ account.conf already exists, skipping${NC}"
fi

# Create symlink for easy access
echo -e "${BLUE}[5/6] Creating command symlink...${NC}"
ln -sf "$ACME_INSTALL_DIR/acme.sh" /usr/local/bin/acme.sh
echo -e "${GREEN}✓ Symlink created: /usr/local/bin/acme.sh${NC}"

# Set proper permissions
echo -e "${BLUE}[6/6] Setting permissions...${NC}"
chown -R root:root "$ACME_INSTALL_DIR"
chmod -R 755 "$ACME_INSTALL_DIR"
chmod 600 "$ACME_DATA_DIR/account.conf" 2>/dev/null || true
echo -e "${GREEN}✓ Permissions set${NC}"

# Verify installation
echo -e "${BLUE}[7/7] Verifying installation...${NC}"

if [ -x "$ACME_INSTALL_DIR/acme.sh" ]; then
    ACME_VERSION=$("$ACME_INSTALL_DIR/acme.sh" --version 2>&1 | head -1)
    echo -e "${GREEN}✓ Installation successful!${NC}"
    echo ""
    echo "Installed: $ACME_VERSION"
    echo "Location: $ACME_INSTALL_DIR"
    echo "Config: $ACME_DATA_DIR/account.conf"
    echo "Certificates: $ACME_DATA_DIR/"
else
    echo -e "${RED}✗ Installation verification failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo -e "${YELLOW}What's next:${NC}"
echo ""
echo "1. Your Docker container will continue to handle certificate issuance and renewal"
echo "2. Native acme.sh will handle deployment to DSM"
echo "3. Both share the same certificate storage: $ACME_DATA_DIR"
echo ""
echo -e "${BLUE}To test the deployment:${NC}"
echo "  sudo $PROJECT_DIR/scripts/deploy-to-dsm.sh"
echo ""
echo -e "${BLUE}To view available commands:${NC}"
echo "  acme.sh --help"
echo ""
echo -e "${BLUE}To list certificates:${NC}"
echo "  acme.sh --list --home $ACME_INSTALL_DIR --config-home $ACME_DATA_DIR"
echo ""
echo -e "${YELLOW}Note: Do NOT use native acme.sh for issuing or renewing certificates.${NC}"
echo -e "${YELLOW}      Use the Docker-based scripts: issue-cert.sh and renew-cert.sh${NC}"
echo ""

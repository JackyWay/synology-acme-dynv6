#!/bin/bash

################################################################################
# Certificate Deployment Script for Synology DSM
#
# This script deploys the issued certificate to Synology DSM using the
# native acme.sh installation with the Synology deployment hook.
#
# Requirements:
# - Native acme.sh installed (run ./scripts/install-acme-native.sh first)
# - Root access (for temp admin mode)
# - Certificate issued via Docker (run ./scripts/issue-cert.sh first)
#
# Usage: sudo ./deploy-to-dsm.sh
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Native acme.sh paths
ACME_INSTALL_DIR="/usr/local/share/acme.sh"
ACME_DATA_DIR="$PROJECT_DIR/acme-data"
ACME_SH="$ACME_INSTALL_DIR/acme.sh"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
else
    echo -e "${RED}Error: .env file not found at $PROJECT_DIR/.env${NC}"
    exit 1
fi

# Validate required environment variables
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: DOMAIN is not set in .env file${NC}"
    exit 1
fi

# Set defaults
SYNO_USE_TEMP_ADMIN="${SYNO_USE_TEMP_ADMIN:-1}"
SYNO_SCHEME="${SYNO_SCHEME:-http}"
SYNO_HOSTNAME="${SYNO_HOSTNAME:-localhost}"
SYNO_PORT="${SYNO_PORT:-5000}"
SYNO_CERTIFICATE="${SYNO_CERTIFICATE:-acme.sh}"
SYNO_CREATE="${SYNO_CREATE:-1}"

echo -e "${GREEN}=== Starting Certificate Deployment to DSM ===${NC}"
echo "Domain: $DOMAIN"
echo "DSM URL: $SYNO_SCHEME://$SYNO_HOSTNAME:$SYNO_PORT"
echo "Certificate Description: $SYNO_CERTIFICATE"
echo "Deployment Method: Native acme.sh"
echo ""

# Check if native acme.sh is installed
if [ ! -f "$ACME_SH" ]; then
    echo -e "${RED}Error: Native acme.sh is not installed${NC}"
    echo "Please run: sudo $SCRIPT_DIR/install-acme-native.sh"
    exit 1
fi

echo -e "${GREEN}✓ Native acme.sh found at $ACME_SH${NC}"

# Check if certificate exists
echo -e "${YELLOW}Verifying certificate exists...${NC}"
if [ ! -f "$ACME_DATA_DIR/${DOMAIN}/${DOMAIN}.cer" ]; then
    echo -e "${RED}Error: Certificate not found for $DOMAIN${NC}"
    echo "Expected path: $ACME_DATA_DIR/${DOMAIN}/${DOMAIN}.cer"
    echo "Please run ./scripts/issue-cert.sh first to issue a certificate"
    exit 1
fi

echo -e "${GREEN}✓ Certificate found${NC}"
echo ""

# Prepare deployment command based on authentication method
if [ "$SYNO_USE_TEMP_ADMIN" = "1" ]; then
    echo -e "${YELLOW}Using temporary admin mode (requires root)...${NC}"

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: Temporary admin mode requires root privileges${NC}"
        echo "Please run this script with sudo: sudo ./scripts/deploy-to-dsm.sh"
        exit 1
    fi

    # Export environment variables for acme.sh
    export SYNO_USE_TEMP_ADMIN="$SYNO_USE_TEMP_ADMIN"
    export SYNO_SCHEME="$SYNO_SCHEME"
    export SYNO_HOSTNAME="$SYNO_HOSTNAME"
    export SYNO_PORT="$SYNO_PORT"
    export SYNO_CERTIFICATE="$SYNO_CERTIFICATE"
    export SYNO_CREATE="$SYNO_CREATE"

    # Deploy with native acme.sh using temp admin
    "$ACME_SH" --deploy \
        -d "$DOMAIN" \
        --deploy-hook synology_dsm \
        --home "$ACME_INSTALL_DIR" \
        --config-home "$ACME_DATA_DIR" \
        --cert-home "$ACME_DATA_DIR"

else
    echo -e "${YELLOW}Using provided credentials...${NC}"

    # Validate credentials
    if [ -z "$SYNO_USERNAME" ] || [ -z "$SYNO_PASSWORD" ]; then
        echo -e "${RED}Error: SYNO_USERNAME and SYNO_PASSWORD must be set when not using temp admin${NC}"
        echo "Either:"
        echo "1. Set SYNO_USE_TEMP_ADMIN=1 in .env and run with sudo"
        echo "2. Set SYNO_USERNAME and SYNO_PASSWORD in .env"
        exit 1
    fi

    # Export environment variables for acme.sh
    export SYNO_USERNAME="$SYNO_USERNAME"
    export SYNO_PASSWORD="$SYNO_PASSWORD"
    export SYNO_SCHEME="$SYNO_SCHEME"
    export SYNO_HOSTNAME="$SYNO_HOSTNAME"
    export SYNO_PORT="$SYNO_PORT"
    export SYNO_CERTIFICATE="$SYNO_CERTIFICATE"
    export SYNO_CREATE="$SYNO_CREATE"
    export SYNO_DEVICE_NAME="${SYNO_DEVICE_NAME:-}"
    export SYNO_DEVICE_ID="${SYNO_DEVICE_ID:-}"
    export SYNO_OTP_CODE="${SYNO_OTP_CODE:-}"

    # Deploy with native acme.sh using credentials
    "$ACME_SH" --deploy \
        -d "$DOMAIN" \
        --deploy-hook synology_dsm \
        --home "$ACME_INSTALL_DIR" \
        --config-home "$ACME_DATA_DIR" \
        --cert-home "$ACME_DATA_DIR"
fi

# Check deployment status
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Certificate deployed to DSM successfully!${NC}"
    echo ""
    echo "You can now access your DSM using HTTPS with the new certificate."
    echo ""
    echo "To verify:"
    echo "1. Open DSM Control Panel → Security → Certificate"
    echo "2. Look for certificate named: $SYNO_CERTIFICATE"
    echo "3. Check the domain and expiration date"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Certificate deployment failed${NC}"
    echo ""
    echo "Common issues:"
    echo "1. Native acme.sh not installed - run: sudo $SCRIPT_DIR/install-acme-native.sh"
    echo "2. Incorrect DSM credentials"
    echo "3. DSM not accessible at $SYNO_SCHEME://$SYNO_HOSTNAME:$SYNO_PORT"
    echo "4. User does not have admin privileges"
    echo "5. 2FA enabled but OTP code not provided"
    echo ""
    echo "For temp admin mode (requires native acme.sh on DSM):"
    echo "- Ensure you run this script as root (sudo)"
    echo "- Verify SYNO_HOSTNAME is 'localhost' or '127.0.0.1'"
    echo "- Native acme.sh must be installed on DSM to access DSM system tools"
    echo ""
    echo "For credential mode:"
    echo "- Verify SYNO_USERNAME and SYNO_PASSWORD are correct"
    echo "- If 2FA is enabled, set SYNO_OTP_CODE or SYNO_DEVICE_ID"
    echo ""
    exit 1
fi

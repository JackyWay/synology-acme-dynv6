#!/bin/bash

################################################################################
# Certificate Issuance Script for Synology DSM
#
# This script issues a new SSL certificate using acme.sh with Let's Encrypt
# and dynv6 DNS-01 validation.
#
# Usage: ./issue-cert.sh
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

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
else
    echo -e "${RED}Error: .env file not found at $PROJECT_DIR/.env${NC}"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi

# Validate required environment variables
if [ -z "$DYNV6_TOKEN" ]; then
    echo -e "${RED}Error: DYNV6_TOKEN is not set in .env file${NC}"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: DOMAIN is not set in .env file${NC}"
    exit 1
fi

if [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: EMAIL is not set in .env file${NC}"
    exit 1
fi

# Set defaults
ACME_SERVER="${ACME_SERVER:-letsencrypt}"

echo -e "${GREEN}=== Starting Certificate Issuance ===${NC}"
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "DNS Provider: dynv6"
echo "CA Server: $ACME_SERVER"
echo ""

# Check if Docker container is running
if ! docker ps | grep -q acme-sh; then
    echo -e "${RED}Error: acme.sh container is not running${NC}"
    echo "Please start it with: docker-compose up -d"
    exit 1
fi

# Register account with Let's Encrypt if not already registered
echo -e "${YELLOW}Checking acme.sh account registration...${NC}"
docker exec acme-sh acme.sh --register-account -m "$EMAIL" --server "$ACME_SERVER" || true

# Issue certificate with DNS-01 challenge via dynv6
echo -e "${YELLOW}Issuing certificate for $DOMAIN...${NC}"
echo "This may take a few minutes as DNS records need to propagate."
echo ""

docker exec -e DYNV6_TOKEN="$DYNV6_TOKEN" acme-sh acme.sh \
    --issue \
    --dns dns_dynv6 \
    -d "$DOMAIN" \
    ${ADDITIONAL_DOMAINS} \
    --server "$ACME_SERVER" \
    --keylength 2048 \
    --force

# Check if certificate was issued successfully
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Certificate issued successfully!${NC}"
    echo ""
    echo "Certificate details:"
    docker exec acme-sh acme.sh --info -d "$DOMAIN"
    echo ""
    echo -e "${GREEN}Next step: Deploy the certificate to DSM${NC}"
    echo "Run: ./scripts/deploy-to-dsm.sh"
else
    echo ""
    echo -e "${RED}✗ Certificate issuance failed${NC}"
    echo "Please check the error messages above."
    echo ""
    echo "Common issues:"
    echo "1. Invalid dynv6 token - verify at https://dynv6.com/keys"
    echo "2. Domain not owned by your dynv6 account"
    echo "3. DNS API rate limiting - wait and try again"
    echo ""
    exit 1
fi

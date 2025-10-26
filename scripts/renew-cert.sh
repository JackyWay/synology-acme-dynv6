#!/bin/bash

################################################################################
# Certificate Renewal Script for Synology DSM
#
# This script checks if certificates need renewal and automatically renews them
# if they expire in less than 30 days. After successful renewal, it deploys
# the new certificate to DSM using the native acme.sh installation.
#
# Workflow:
# 1. Docker acme.sh handles certificate renewal (DNS validation)
# 2. Native acme.sh handles deployment to DSM (requires DSM system tools)
#
# Requirements:
# - Docker container running (for certificate renewal)
# - Native acme.sh installed (for deployment to DSM)
# - Root access if using SYNO_USE_TEMP_ADMIN=1 (recommended)
#
# Usage:
#   ./renew-cert.sh [--force]     # For credential mode
#   sudo ./renew-cert.sh [--force] # For temp admin mode (recommended)
#
# Options:
#   --force: Force renewal even if certificate is not expiring soon
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
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/renewal.log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to log colored console output
log_console() {
    local color="$1"
    shift
    local message="$@"
    echo -e "${color}${message}${NC}"
}

# Parse command line arguments
FORCE_RENEW=0
if [ "$1" = "--force" ]; then
    FORCE_RENEW=1
    log "INFO" "Force renewal requested"
fi

log "INFO" "=== Certificate Renewal Check Started ==="

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
    log "INFO" "Environment variables loaded"
else
    log "ERROR" ".env file not found at $PROJECT_DIR/.env"
    log_console "$RED" "Error: .env file not found"
    exit 1
fi

# Validate required environment variables
if [ -z "$DOMAIN" ]; then
    log "ERROR" "DOMAIN is not set in .env file"
    log_console "$RED" "Error: DOMAIN is not set"
    exit 1
fi

log "INFO" "Checking certificate for domain: $DOMAIN"

# Check if Docker container is running
if ! docker ps | grep -q acme-sh; then
    log "ERROR" "acme.sh container is not running"
    log_console "$RED" "Error: acme.sh container is not running"
    log "INFO" "Attempting to start container..."
    cd "$PROJECT_DIR"
    docker-compose up -d
    sleep 5

    if ! docker ps | grep -q acme-sh; then
        log "ERROR" "Failed to start acme.sh container"
        exit 1
    fi
    log "INFO" "Container started successfully"
fi

# Check certificate status
log "INFO" "Checking certificate expiration status..."
CERT_INFO=$(docker exec acme-sh acme.sh --list | grep "$DOMAIN" || true)

if [ -z "$CERT_INFO" ]; then
    log "ERROR" "No certificate found for $DOMAIN"
    log_console "$RED" "Error: No certificate found for $DOMAIN"
    log "INFO" "Please run ./scripts/issue-cert.sh first to issue a certificate"
    exit 1
fi

log "INFO" "Certificate found: $CERT_INFO"

# Renew certificate
if [ $FORCE_RENEW -eq 1 ]; then
    log "INFO" "Force renewing certificate for $DOMAIN..."
    log_console "$YELLOW" "Force renewing certificate..."

    RENEW_OUTPUT=$(docker exec -e DYNV6_TOKEN="$DYNV6_TOKEN" acme-sh acme.sh \
        --renew \
        -d "$DOMAIN" \
        --force 2>&1)
    RENEW_STATUS=$?
else
    log "INFO" "Checking if renewal is needed (< 30 days to expiry)..."
    log_console "$BLUE" "Checking certificate renewal..."

    RENEW_OUTPUT=$(docker exec -e DYNV6_TOKEN="$DYNV6_TOKEN" acme-sh acme.sh \
        --renew \
        -d "$DOMAIN" 2>&1)
    RENEW_STATUS=$?
fi

# Log the renewal output
echo "$RENEW_OUTPUT" >> "$LOG_FILE"

# Check renewal status
if [ $RENEW_STATUS -eq 0 ]; then
    if echo "$RENEW_OUTPUT" | grep -q "Cert success"; then
        log "INFO" "Certificate renewed successfully!"
        log_console "$GREEN" "✓ Certificate renewed successfully!"

        # Deploy to DSM
        log "INFO" "Deploying renewed certificate to DSM..."
        log_console "$YELLOW" "Deploying certificate to DSM..."

        if "$SCRIPT_DIR/deploy-to-dsm.sh"; then
            log "INFO" "Certificate deployed to DSM successfully"
            log_console "$GREEN" "✓ Certificate deployed to DSM successfully!"
        else
            log "ERROR" "Failed to deploy certificate to DSM"
            log_console "$RED" "✗ Failed to deploy certificate to DSM"
            log "INFO" "You may need to deploy manually: ./scripts/deploy-to-dsm.sh"
            exit 1
        fi
    elif echo "$RENEW_OUTPUT" | grep -q "Cert skipped" || echo "$RENEW_OUTPUT" | grep -q "Skip"; then
        log "INFO" "Certificate is still valid, renewal not needed"
        log_console "$GREEN" "✓ Certificate is still valid (renewal not needed)"
    else
        log "INFO" "Certificate renewal completed"
        log_console "$GREEN" "✓ Certificate renewal completed"
    fi
elif [ $RENEW_STATUS -eq 2 ]; then
    # Exit code 2 means cert is still valid, not an error
    log "INFO" "Certificate is still valid, renewal not needed"
    log_console "$GREEN" "✓ Certificate is still valid (> 30 days remaining)"
else
    log "ERROR" "Certificate renewal failed with exit code $RENEW_STATUS"
    log_console "$RED" "✗ Certificate renewal failed"
    log "ERROR" "Renewal output: $RENEW_OUTPUT"

    log_console "$YELLOW" "Common issues:"
    log_console "$YELLOW" "1. DNS API rate limiting - wait and try again later"
    log_console "$YELLOW" "2. Invalid dynv6 token - verify at https://dynv6.com/keys"
    log_console "$YELLOW" "3. Network connectivity issues"

    exit 1
fi

# Show certificate info
log "INFO" "Certificate information:"
CERT_INFO_DETAIL=$(docker exec acme-sh acme.sh --info -d "$DOMAIN" 2>&1 || true)
echo "$CERT_INFO_DETAIL" | tee -a "$LOG_FILE"

log "INFO" "=== Certificate Renewal Check Completed ==="
log_console "$GREEN" "✓ Renewal check completed successfully"

exit 0

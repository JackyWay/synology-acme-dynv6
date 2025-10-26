# Synology DSM SSL Certificate Automation - Implementation Plan

## Overview
Automated SSL certificate issuance and renewal for Synology DSM 6.2.3 using acme.sh with Let's Encrypt, dynv6 DNS validation, and **hybrid architecture** (Docker for certificate issuance/renewal + native acme.sh for DSM deployment).

## Requirements
- **NAS**: Synology DSM 6.2.3 or later
- **Domain**: example.v6.army (dynv6 DDNS)
- **Connectivity**: IPv6 only for public access
- **CA**: Let's Encrypt
- **DNS Provider**: dynv6.com
- **Deployment**: Hybrid architecture (Docker + native acme.sh)
- **Auto-renewal**: Daily check via DSM Task Scheduler

## Architecture: Hybrid Approach

**Why Hybrid?**
- **Docker**: Certificate issuance/renewal in isolated environment
- **Native acme.sh**: DSM deployment with access to system tools (synouser, synogroup, synosetkeyvalue)
- **Shared Storage**: Both installations use the same certificate directory (no duplication)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Certificate Lifecycle                       │
└─────────────────────────────────────────────────────────────────┘

Step 1: Issue/Renew (Docker)
┌──────────────┐   DNS-01    ┌──────────────┐   Certificate
│   Docker     │────────────▶│ Let's Encrypt│───────────────┐
│   acme.sh    │   via dynv6 │   + DNS API  │               │
└──────────────┘             └──────────────┘               ▼
                                                    ┌──────────────┐
                                                    │  acme-data/  │
                                                    │   (shared)   │
                                                    └──────────────┘
                                                             │
Step 2: Deploy (Native)                                     │
┌──────────────┐   Read certs ┌──────────────┐   Deploy    │
│   Native     │◀──────────────│  acme-data/  │             │
│   acme.sh    │               │   (shared)   │◀────────────┘
│ + DSM tools  │               └──────────────┘
└──────────────┘
       │
       │ Has access to:
       │ - synouser
       │ - synogroup
       │ - synosetkeyvalue
       ▼
┌──────────────┐
│  Synology    │
│     DSM      │
│  Cert Store  │
└──────────────┘
```

## Implementation Steps

### Phase 1: Preparation (Before running on NAS)
1. ✅ Verify acme.sh supports dynv6 DNS API
2. ✅ Verify Synology DSM deployment hook exists
3. ✅ Create project directory structure
4. ✅ Write implementation documentation

### Phase 2: Configuration Files
1. Create `.env.example` template with required variables
2. Create `docker-compose.yml` for acme.sh container
3. Create `.env` from template (user fills in actual values)

### Phase 3: Script Development
1. **install-acme-native.sh** (NEW - Critical for hybrid architecture)
   - Download and install native acme.sh on DSM
   - Configure to use shared certificate directory
   - Set up symlinks and permissions
   - Required for SYNO_USE_TEMP_ADMIN=1 mode

2. **issue-cert.sh**
   - Initial certificate issuance (uses Docker)
   - DNS-01 challenge via dynv6 API
   - Save certificate to shared acme-data/ volume

3. **renew-cert.sh**
   - Check certificate expiration (runs in Docker)
   - Renew if < 30 days remaining
   - Call deploy script if renewed (uses native acme.sh)

4. **deploy-to-dsm.sh**
   - Use native acme.sh Synology deployment hook
   - Access to DSM system tools for temp admin mode
   - Upload certificate to DSM
   - Restart DSM services

### Phase 4: Deployment on NAS
1. Copy files to `/volume1/docker/synology-acme/`
2. Configure environment variables in `.env`
3. Set file permissions: `chmod +x scripts/*.sh` and `chmod 600 .env`
4. Start Docker container: `docker-compose up -d`
5. **Install native acme.sh**: `sudo ./scripts/install-acme-native.sh` (REQUIRED)
6. Run initial certificate issuance: `./scripts/issue-cert.sh`
7. Deploy to DSM: `sudo ./scripts/deploy-to-dsm.sh`
8. Test renewal script manually: `sudo ./scripts/renew-cert.sh --force`
9. Configure DSM Task Scheduler for daily renewal (no crontab available on DSM)

### Phase 5: Testing & Validation
1. Test initial certificate issuance
2. Test certificate deployment to DSM
3. Verify DSM accepts and uses the certificate
4. Test renewal process (force renew)
5. Verify Task Scheduler execution

## File Structure

```
/home/dk/git/private/synology-acme/
├── plan.md                    # This file
├── README.md                  # User guide and documentation
├── README.zh-CN.md           # Chinese documentation
├── QUICK-START.md            # Quick start guide
├── QUICK-START.zh-CN.md      # Chinese quick start guide
├── RELEASE-PREPARATION.md    # Public release guide
├── .env.example               # Environment variables template
├── docker-compose.yml         # Docker container configuration
├── docs/
│   └── DEPLOYMENT-OPTIONS.md # Architecture and deployment details
└── scripts/
    ├── install-acme-native.sh # Install native acme.sh (REQUIRED)
    ├── issue-cert.sh         # Initial certificate issuance (Docker)
    ├── renew-cert.sh         # Daily renewal check (Docker + native)
    └── deploy-to-dsm.sh      # Deploy certificate to DSM (native)
```

## On NAS (Runtime Structure)

```
/volume1/docker/synology-acme/          # Project root
├── docker-compose.yml                   # Docker configuration
├── .env                                 # User's actual credentials (600)
├── README.md                            # Documentation
├── QUICK-START.md                       # Quick start guide
├── docs/
│   └── DEPLOYMENT-OPTIONS.md           # Architecture details
├── scripts/
│   ├── install-acme-native.sh          # Install native acme.sh
│   ├── issue-cert.sh                   # Issue certificate (Docker)
│   ├── renew-cert.sh                   # Renew (Docker + native)
│   └── deploy-to-dsm.sh                # Deploy (native)
├── acme-data/                          # Shared certificate storage
│   ├── account.conf                    # acme.sh config
│   └── example.v6.army/               # Domain certificates
│       ├── example.v6.army.cer        # Certificate
│       ├── example.v6.army.key        # Private key
│       ├── ca.cer                      # CA certificate
│       └── fullchain.cer               # Full chain
└── logs/                               # Log files
    ├── renewal.log                     # Renewal logs
    └── acme-native.log                 # Native acme.sh logs

/usr/local/share/acme.sh/               # Native installation (on DSM host)
├── acme.sh                             # Main script
├── deploy/
│   └── synology_dsm.sh                # Synology deployment hook
└── [other acme.sh files]

/usr/local/bin/acme.sh                  # Symlink to native acme.sh
```

## Security Considerations

1. **API Token Storage**: Store DYNV6_TOKEN in `.env` file with restricted permissions (600)
2. **DSM Credentials**: Use SYNO_USE_TEMP_ADMIN=1 to avoid storing admin passwords
3. **File Permissions**: Ensure certificate files are readable only by root
4. **Docker Isolation**: Run acme.sh in isolated container
5. **Backup**: Keep backup of certificates in case of failure

## Advantages of Hybrid Architecture

1. **Best of Both Worlds**: Docker isolation for certificates + DSM integration for deployment
2. **Secure Deployment**: SYNO_USE_TEMP_ADMIN=1 mode (no stored passwords)
3. **Easy Updates**: Update Docker image (`docker-compose pull`) without affecting native installation
4. **Shared Storage**: No certificate duplication, single source of truth
5. **Automated Renewal**: Daily checks ensure certificates never expire
6. **No Manual Intervention**: Fully automated after initial setup
7. **IPv6 Compatible**: DNS validation works regardless of network connectivity
8. **Access to DSM Tools**: Native acme.sh has access to synouser, synogroup, synosetkeyvalue
9. **Minimal System Changes**: Only native acme.sh installed, no other modifications

## Maintenance

- **Certificate Renewal**: Automatic, checked daily
- **Update acme.sh**: `docker-compose pull && docker-compose up -d`
- **View Logs**: Check `/volume1/docker/synology-acme/logs/renewal.log`
- **Manual Renewal**: Run `./scripts/renew-cert.sh --force`

## Troubleshooting

1. **Certificate not issued**: Check dynv6 token validity
2. **Deployment failed**: Verify DSM admin credentials
3. **Container won't start**: Check docker-compose.yml and .env syntax
4. **DNS validation timeout**: Verify dynv6 API access and domain ownership

## Next Steps

1. Fill in environment variables in `.env`
2. Follow README.md or QUICK-START.md for deployment instructions
3. Install native acme.sh: `sudo ./scripts/install-acme-native.sh`
4. Run initial certificate issuance: `./scripts/issue-cert.sh`
5. Deploy to DSM: `sudo ./scripts/deploy-to-dsm.sh`
6. Configure DSM Task Scheduler for daily renewals (crontab not available on DSM)

## Key Differences from Standard acme.sh Deployment

This hybrid architecture solves a critical limitation:
- **Problem**: `SYNO_USE_TEMP_ADMIN=1` fails in Docker because DSM system tools (synouser, synogroup, synosetkeyvalue) are only available on the host
- **Solution**: Use Docker for certificate operations + native acme.sh for deployment
- **Result**: Secure deployment without storing admin passwords

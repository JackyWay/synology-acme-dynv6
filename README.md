# Synology DSM Automated SSL Certificate Management

Automated SSL certificate issuance and renewal for Synology DSM 6.2.3 using acme.sh, Let's Encrypt, and dynv6 DNS validation.

## Features

- **Automated Certificate Issuance**: Initial certificate generation with Let's Encrypt
- **Automatic Renewal**: Daily checks and renewal before expiration (30 days)
- **DNS-01 Challenge**: Works with IPv6-only connectivity via dynv6 DNS API
- **DSM Integration**: Automatically deploys certificates to Synology DSM web interface
- **Hybrid Architecture**: Docker for certificate issuance/renewal, native acme.sh for DSM deployment
- **Secure Deployment**: Supports temporary admin mode (no stored passwords required)
- **Zero Downtime**: Certificates renewed and deployed without manual intervention

## Prerequisites

### On Synology NAS
- Synology DSM 6.2.3 or later
- Docker package installed
- SSH access enabled
- Root or admin access

### External Services
- Domain registered with [dynv6.com](https://dynv6.com) (e.g., example.v6.army)
- dynv6 API token (get from https://dynv6.com/keys)

## Quick Start

### 1. Clone or Copy Files to NAS

```bash
# On your NAS, create the directory
mkdir -p /volume1/docker/synology-acme
cd /volume1/docker/synology-acme

# Copy all files from this repository to the above directory
```

### 2. Configure Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit the .env file with your actual credentials
vi .env
```

Required variables:
- `DYNV6_TOKEN`: Your dynv6 API token from https://dynv6.com/keys
- `DOMAIN`: Your domain name (e.g., example.v6.army)
- `EMAIL`: Your email for Let's Encrypt notifications

Optional variables:
- `SYNO_USERNAME`: DSM admin username (leave empty to use temp admin)
- `SYNO_PASSWORD`: DSM admin password (leave empty to use temp admin)

### 3. Set File Permissions

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Secure the .env file
chmod 600 .env

# Create directories for data and logs
mkdir -p acme-data logs
```

### 4. Start Docker Container

```bash
# Start the acme.sh container
docker-compose up -d

# Verify container is running
docker-compose ps
```

### 5. Install Native acme.sh for Deployment

```bash
# Install native acme.sh on DSM (required for deployment)
sudo ./scripts/install-acme-native.sh
```

This will:
1. Download and install acme.sh to `/usr/local/share/acme.sh`
2. Configure it to use the same certificate directory as Docker
3. Set up symlinks and proper permissions
4. No duplicate certificates - both installations share the same storage

**Why native acme.sh?**
- `SYNO_USE_TEMP_ADMIN=1` requires DSM system tools (synouser, synogroup, synosetkeyvalue)
- These tools only exist on DSM host, not inside Docker container
- Native installation allows secure deployment without storing admin passwords

### 6. Issue Initial Certificate

```bash
# Run the certificate issuance script (uses Docker)
./scripts/issue-cert.sh
```

This will:
1. Connect to dynv6 API
2. Request certificate from Let's Encrypt
3. Complete DNS-01 validation
4. Save certificate to `acme-data/` (shared storage)

### 7. Deploy Certificate to DSM

```bash
# Deploy the certificate to Synology DSM (uses native acme.sh)
sudo ./scripts/deploy-to-dsm.sh
```

This will:
1. Use native acme.sh with DSM deployment hook
2. Upload certificate to DSM certificate store
3. Restart DSM web services
4. Verify deployment success

**Note:** Requires root/sudo for temporary admin mode (recommended for security)

### 8. Configure Automatic Renewal

**Important:** Use DSM Task Scheduler for automated renewals on Synology NAS. The `crontab` command is **not available** on Synology DSM.

#### Using DSM Task Scheduler (ONLY Method for Synology)

1. Open DSM Control Panel → Task Scheduler
2. Create → Scheduled Task → User-defined script
3. Configure the task:
   - **General**:
     - Task: SSL Certificate Renewal
     - User: root
     - Enabled: ✓
   - **Schedule**:
     - Run on the following days: Daily
     - First run time: 02:00 (2:00 AM) or any preferred time
     - Frequency: Every day
   - **Task Settings**:
     - User-defined script:
       ```bash
       bash /volume1/docker/synology-acme/scripts/renew-cert.sh
       ```
4. Click OK to save

#### Understanding Daily Renewal Checks

**Why run daily when certificates last 90 days?**

The renewal script is intelligent:
- **Runs daily** to check certificate expiration
- **Only renews when < 30 days** remaining (Let's Encrypt default)
- **Daily check-only runs** take < 1 second with minimal resources
- **Provides retry opportunities** if a renewal attempt fails

**Example Timeline:**
- Certificate issued: 2025-10-26
- Certificate expires: 2026-01-24 (90 days)
- Daily checks: 2025-10-26 to 2025-12-24 (script exits immediately, no action)
- **First renewal: ~2025-12-25** (when < 30 days remaining)
- Subsequent renewals: Every 60 days automatically

**Benefits of Daily Checks:**
- ✓ Multiple retry chances if renewal fails
- ✓ Handles DSM clock drift or downtime
- ✓ Standard Let's Encrypt best practice
- ✓ Negligible performance impact (< 0.01% CPU, < 1 second)

### 9. Test Renewal Process

#### Test the Scheduled Task

**Option 1: Test via DSM Task Scheduler (Recommended)**
1. Go to DSM Control Panel → Task Scheduler
2. Select your "SSL Certificate Renewal" task
3. Click "Run" (运行) button
4. Check Task Scheduler → Action → View Results to see execution log
5. Verify in `logs/renewal.log`

**What to expect when testing a fresh certificate:**
Since your certificate was just issued, the script will:
- Check certificate expiration
- Find that > 30 days remain
- Exit immediately with message: "✓ Certificate is still valid"
- No renewal will occur (this is correct behavior!)

#### Test Full Renewal (Optional)

To test the complete renewal + deployment workflow:

```bash
# Switch to root
sudo su -
cd /volume1/docker/synology-acme

# Force renewal even though certificate is valid
./scripts/renew-cert.sh --force

# Check logs
tail -f logs/renewal.log
```

This will:
1. Force certificate renewal via Docker (DNS-01 validation)
2. Deploy renewed certificate to DSM using native acme.sh
3. Restart DSM web services
4. Log all actions to `logs/renewal.log`

**Note:** Use `sudo su -` (switch to root) if you have `SYNO_USE_TEMP_ADMIN=1` in your `.env` file

## File Structure

```
/volume1/docker/synology-acme/
├── docker-compose.yml         # Docker container configuration
├── .env                       # Your credentials (not in git)
├── .env.example              # Template for environment variables
├── README.md                 # This file
├── QUICK-START.md            # Quick start guide
├── docs/
│   └── DEPLOYMENT-OPTIONS.md # Deployment architecture explained
├── scripts/
│   ├── install-acme-native.sh # Install native acme.sh on DSM
│   ├── issue-cert.sh        # Initial certificate issuance (Docker)
│   ├── renew-cert.sh        # Renewal check and execution (Docker + native)
│   └── deploy-to-dsm.sh     # Deploy certificate to DSM (native)
├── acme-data/               # Certificate storage (shared between Docker & native)
│   ├── account.conf         # acme.sh account configuration
│   └── example.v6.army/       # Your domain's certificates
│       ├── example.v6.army.cer      # Certificate
│       ├── example.v6.army.key      # Private key
│       ├── ca.cer                  # CA certificate
│       └── fullchain.cer           # Full certificate chain
└── logs/                     # Log files
    ├── renewal.log           # Renewal process logs
    └── acme-native.log       # Native acme.sh logs

Native acme.sh installation (on DSM host):
/usr/local/share/acme.sh/    # Native acme.sh installation
/usr/local/bin/acme.sh       # Symlink to native acme.sh
```

## Usage

### Manual Certificate Issuance

```bash
./scripts/issue-cert.sh
```

### Manual Certificate Renewal

```bash
# Check and renew if needed (< 30 days to expiry)
./scripts/renew-cert.sh

# Force renewal regardless of expiration date
./scripts/renew-cert.sh --force
```

### Manual Deployment to DSM

```bash
# With temp admin mode (recommended)
sudo ./scripts/deploy-to-dsm.sh

# With credential mode
./scripts/deploy-to-dsm.sh
```

### Check Certificate Expiration

```bash
# Using OpenSSL
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -dates

# Using acme.sh in container
docker-compose exec acme.sh --list
```

### View Logs

```bash
# Renewal logs
tail -f logs/renewal.log

# Docker container logs
docker-compose logs -f acme.sh
```

## Architecture: Hybrid Approach

This project uses a **hybrid architecture** combining Docker and native installations:

### Why Hybrid?

**Docker for Certificate Issuance/Renewal:**
- Clean, isolated environment
- Easy to update and maintain
- No system modifications required
- Perfect for DNS-01 validation

**Native acme.sh for DSM Deployment:**
- Access to DSM system tools (synouser, synogroup, synosetkeyvalue)
- Enables `SYNO_USE_TEMP_ADMIN=1` mode (no stored passwords)
- Direct integration with Synology DSM APIs
- Secure temporary admin user creation

### Shared Certificate Storage

Both installations share the same certificate directory (`acme-data/`):
- No certificate duplication
- Docker issues/renews certificates
- Native acme.sh deploys certificates
- Single source of truth for all certificates

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Certificate Lifecycle                     │
└─────────────────────────────────────────────────────────────────┘

1. Issue/Renew (Docker):
   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
   │ Docker       │ ───▶ │ Let's        │ ───▶ │ acme-data/   │
   │ acme.sh      │      │ Encrypt      │      │ (shared)     │
   └──────────────┘      └──────────────┘      └──────────────┘
         │                                              │
         │ DNS-01 validation via dynv6                 │
         └─────────────────────────────────────────────┘

2. Deploy (Native):
   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
   │ acme-data/   │ ───▶ │ Native       │ ───▶ │ Synology     │
   │ (shared)     │      │ acme.sh      │      │ DSM          │
   └──────────────┘      └──────────────┘      └──────────────┘
                                │
                                │ Uses DSM system tools
                                │ (temp admin support)
                                └─────────────────────────────
```

For more details, see [docs/DEPLOYMENT-OPTIONS.md](docs/DEPLOYMENT-OPTIONS.md)

## Configuration Details

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DYNV6_TOKEN` | Yes | - | dynv6 API token from https://dynv6.com/keys |
| `DOMAIN` | Yes | - | Your domain name (e.g., example.v6.army) |
| `EMAIL` | Yes | - | Email for Let's Encrypt notifications |
| `SYNO_USERNAME` | No | (temp admin) | DSM admin username |
| `SYNO_PASSWORD` | No | (temp admin) | DSM admin password |
| `SYNO_SCHEME` | No | http | DSM connection scheme (http/https) |
| `SYNO_HOSTNAME` | No | localhost | DSM hostname |
| `SYNO_PORT` | No | 5000 | DSM port |
| `SYNO_CERTIFICATE` | No | acme.sh | Certificate description in DSM |
| `ACME_SERVER` | No | letsencrypt | CA server (letsencrypt/letsencrypt_test) |

### Using Temporary Admin (Recommended)

If you leave `SYNO_USERNAME` and `SYNO_PASSWORD` empty, the script will use `SYNO_USE_TEMP_ADMIN=1` mode, which:
- Creates a temporary admin user during deployment
- Doesn't require storing your admin password
- More secure as credentials are not persisted
- Only works when running locally on the NAS

### Using Existing Admin Account

If you prefer to use your existing admin account:
1. Set `SYNO_USERNAME` to your DSM admin username
2. Set `SYNO_PASSWORD` to your DSM admin password
3. If 2FA is enabled, you may need to provide `SYNO_OTP_CODE` or `SYNO_DEVICE_ID`

## Troubleshooting

### Certificate Issuance Failed

**Symptom**: `issue-cert.sh` fails with DNS validation error

**Solutions**:
1. Verify your dynv6 token is correct:
   ```bash
   # Test dynv6 API access
   curl -H "Authorization: Bearer YOUR_TOKEN" https://dynv6.com/api/v2/zones
   ```
2. Check domain ownership at dynv6.com
3. Ensure domain is correctly configured in `.env`
4. Check logs: `docker-compose logs acme.sh`

### Certificate Deployment Failed

**Symptom**: `deploy-to-dsm.sh` fails with authentication error

**Solutions**:
1. If using temp admin mode:
   - Ensure script runs as root: `sudo ./scripts/deploy-to-dsm.sh`
   - Verify DSM is accessible at localhost:5000
2. If using credentials:
   - Verify username and password are correct
   - Check if 2FA is enabled (may need `SYNO_OTP_CODE`)
3. Test DSM API access:
   ```bash
   curl "http://localhost:5000/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query"
   ```

### Docker Container Won't Start

**Symptom**: `docker-compose up -d` fails

**Solutions**:
1. Check Docker is installed and running:
   ```bash
   docker --version
   docker ps
   ```
2. Verify docker-compose.yml syntax:
   ```bash
   docker-compose config
   ```
3. Check .env file syntax (no spaces around `=`)
4. View detailed error: `docker-compose up` (without `-d`)

### Certificate Not Renewing Automatically

**Symptom**: Renewal script doesn't run or fails silently

**Solutions**:
1. Check Task Scheduler status in DSM Control Panel
2. Verify script has execute permissions: `ls -l scripts/renew-cert.sh`
3. Run manually to see errors: `./scripts/renew-cert.sh`
4. Check logs: `cat logs/renewal.log`
5. Ensure path in Task Scheduler is absolute path

### DNS Validation Timeout

**Symptom**: DNS-01 challenge fails with timeout

**Solutions**:
1. dynv6 API may be slow, the script will retry
2. Check dynv6.com status page
3. Verify your domain's DNS is propagated:
   ```bash
   dig _acme-challenge.example.v6.army TXT
   ```
4. Increase timeout in acme.sh (edit scripts if needed)

## Security Best Practices

1. **Protect .env file**:
   ```bash
   chmod 600 .env
   chown root:root .env
   ```

2. **Use temporary admin mode**: Avoid storing admin passwords when possible

3. **Regular backups**: Backup `acme-data/` directory periodically

4. **Monitor logs**: Regularly check `logs/renewal.log` for issues

5. **Restrict SSH access**: Only enable SSH when needed

6. **Keep Docker updated**: Update Docker package in DSM Package Center

## Maintenance

### Update acme.sh

```bash
# Pull latest acme.sh image
docker-compose pull

# Restart container with new image
docker-compose up -d
```

### Backup Certificates

```bash
# Create backup
tar -czf acme-backup-$(date +%Y%m%d).tar.gz acme-data/

# Restore from backup
tar -xzf acme-backup-YYYYMMDD.tar.gz
```

### Change Domain or DNS Provider

1. Stop the container: `docker-compose down`
2. Update `.env` with new values
3. Remove old certificates: `rm -rf acme-data/*`
4. Start container: `docker-compose up -d`
5. Issue new certificate: `./scripts/issue-cert.sh`

### Monitor Certificate Expiration

```bash
# Check expiration date
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -enddate

# List all certificates in acme.sh
docker-compose exec acme.sh --list
```

## Advanced Configuration

### Use Staging Server (Testing)

For testing, use Let's Encrypt staging server to avoid rate limits:

```bash
# In .env file
ACME_SERVER=letsencrypt_test
```

After testing, change back to production:
```bash
ACME_SERVER=letsencrypt
```

### Multiple Domains (SAN Certificate)

To issue a certificate for multiple domains:

1. Update `.env`:
   ```bash
   DOMAIN="example.v6.army"
   ADDITIONAL_DOMAINS="-d www.example.v6.army -d sub.example.v6.army"
   ```

2. All domains must be managed by dynv6 or support the same DNS API

### Custom Certificate Description in DSM

To identify your certificate in DSM:

```bash
# In .env file
SYNO_CERTIFICATE="My Custom Certificate Name"
```

## FAQ

**Q: How often does the certificate renew?**
A: Certificates are checked daily. Let's Encrypt certificates are valid for 90 days and will be renewed when less than 30 days remain.

**Q: What happens if renewal fails?**
A: The script logs the error and will retry the next day. You'll have 30 days to fix issues before expiration.

**Q: Can I use this with ZeroSSL instead of Let's Encrypt?**
A: Yes, modify `issue-cert.sh` to use `--server zerossl` parameter.

**Q: Does this work with DSM 7.x?**
A: This is designed for DSM 6.2.3. For DSM 7.x, you may need to adjust paths and API calls.

**Q: Will this affect my existing DSM certificate?**
A: If `SYNO_CERTIFICATE` matches an existing cert description, it will be updated. Otherwise, a new certificate entry will be created.

**Q: Can I run this without Docker?**
A: Yes, but you'll need to install acme.sh directly on DSM. The Docker method is cleaner and easier to manage.

## Support and Resources

- **acme.sh Documentation**: https://github.com/acmesh-official/acme.sh
- **dynv6 API Docs**: https://dynv6.com/docs/apis
- **Synology DSM Guide**: https://github.com/acmesh-official/acme.sh/wiki/Synology-NAS-Guide
- **Let's Encrypt**: https://letsencrypt.org/

## License

This project uses acme.sh which is licensed under GPLv3. Scripts in this repository are provided as-is for personal use.

## Contributing

If you encounter issues or have improvements:
1. Check existing issues and documentation
2. Test your changes thoroughly
3. Document any modifications
4. Share your solution with the community

## Changelog

- **2025-10-26**: Initial release
  - Docker-based solution
  - dynv6 DNS-01 validation
  - Automatic DSM deployment
  - Daily renewal checks

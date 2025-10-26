# Quick Start Guide - Synology SSL Certificate Automation

This is a condensed guide to get you up and running quickly. For detailed documentation, see [README.md](README.md).

## Prerequisites Checklist

- [ ] Synology DSM 6.2.3 or later installed
- [ ] Docker package installed on Synology
- [ ] SSH access enabled (root access required)
- [ ] Domain registered at dynv6.com (e.g., example.v6.army)
- [ ] dynv6 API token from https://dynv6.com/keys

## Installation Steps (15 minutes)

### 1. Copy files to your NAS

```bash
# On your NAS, create directory
ssh root@your-nas-ip
mkdir -p /volume1/docker/synology-acme
cd /volume1/docker/synology-acme

# Copy all files from this repository
# (Use WinSCP, FileZilla, or rsync to transfer files)
```

### 2. Configure environment

```bash
cd /volume1/docker/synology-acme

# Create .env from template
cp .env.example .env

# Edit with your actual values
vi .env
```

**Minimal .env configuration:**
```bash
DYNV6_TOKEN=your_token_from_dynv6_com
DOMAIN=example.v6.army
EMAIL=your-email@example.com
SYNO_USE_TEMP_ADMIN=1
```

**Secure the file:**
```bash
chmod 600 .env
```

### 3. Start Docker container

```bash
# Start the container
docker-compose up -d

# Verify it's running
docker-compose ps
```

### 4. Install native acme.sh

```bash
# Install native acme.sh for DSM deployment
sudo ./scripts/install-acme-native.sh

# This enables secure deployment without storing passwords
```

**Why?** The native installation gives acme.sh access to DSM system tools needed for `SYNO_USE_TEMP_ADMIN=1` mode.

### 5. Issue certificate

```bash
# Issue your first certificate (uses Docker)
./scripts/issue-cert.sh

# This will take 2-3 minutes
```

### 6. Deploy to DSM

```bash
# Deploy certificate to DSM (uses native acme.sh, requires root)
sudo ./scripts/deploy-to-dsm.sh
```

### 7. Set up automatic renewal

**Important:** The `crontab` command is NOT available on Synology DSM. Use Task Scheduler instead.

**Using DSM Task Scheduler (ONLY Method):**

1. Open DSM → Control Panel → Task Scheduler
2. Create → Scheduled Task → User-defined script
3. General tab:
   - Task: `SSL Certificate Renewal`
   - User: `root`
   - Enabled: ✓
4. Schedule tab:
   - Run on: `Daily`
   - Time: `02:00` (or any preferred time)
5. Task Settings tab:
   - Script:
     ```bash
     bash /volume1/docker/synology-acme/scripts/renew-cert.sh
     ```
6. Click OK

**About Daily Checks:**
The script runs daily but only renews when < 30 days to expiry. Daily check-only runs take < 1 second with minimal resources. This is standard Let's Encrypt best practice.

### 8. Test renewal (optional)

**Test via Task Scheduler (Recommended):**
1. Go to Task Scheduler in DSM
2. Select "SSL Certificate Renewal" task
3. Click "Run" (运行) button
4. View results in Task Scheduler or `logs/renewal.log`

**Expected:** Script will check cert and exit (no renewal needed if cert is fresh)

**Test full renewal via SSH (Optional):**
```bash
# Switch to root and force renewal
sudo su -
cd /volume1/docker/synology-acme
./scripts/renew-cert.sh --force

# Check logs
tail -f logs/renewal.log
```

## Done!

Your certificate will now automatically renew every day before it expires. The certificate is valid for 90 days and will renew when less than 30 days remain.

## Verify Installation

### Check certificate in DSM
1. Open DSM → Control Panel → Security → Certificate
2. Find certificate named "acme.sh"
3. Verify domain and expiration date

### Check certificate files
```bash
ls -lh acme-data/example.v6.army/
```

### Check renewal logs
```bash
tail -50 logs/renewal.log
```

## Common Issues & Quick Fixes

### Issue: "DYNV6_TOKEN is not set"
**Fix:** Edit `.env` and add your dynv6 token from https://dynv6.com/keys

### Issue: "acme.sh container is not running"
**Fix:** Run `docker-compose up -d`

### Issue: "Certificate deployment failed"
**Fix:** Make sure you run with sudo: `sudo ./scripts/deploy-to-dsm.sh`

### Issue: "DNS validation timeout"
**Fix:** Wait 1-2 minutes and try again. dynv6 DNS may need time to propagate.

### Issue: "Permission denied"
**Fix:**
```bash
chmod +x scripts/*.sh
chmod 600 .env
```

## Next Steps

- Read [README.md](README.md) for detailed documentation
- Review [plan.md](plan.md) for architecture details
- Configure your applications to use the new certificate
- Set up monitoring for certificate expiration

## File Structure Overview

```
/volume1/docker/synology-acme/
├── docker-compose.yml         # Container config
├── .env                       # Your settings (KEEP SECRET!)
├── .env.example              # Template
├── README.md                 # Full documentation
├── QUICK-START.md            # This file
├── docs/
│   └── DEPLOYMENT-OPTIONS.md # Architecture details
├── scripts/
│   ├── install-acme-native.sh # Install native acme.sh
│   ├── issue-cert.sh        # Issue certificate (Docker)
│   ├── renew-cert.sh        # Renew certificate (Docker + native)
│   └── deploy-to-dsm.sh     # Deploy to DSM (native)
├── acme-data/               # Certificates (shared storage)
└── logs/                    # Logs (auto-created)

/usr/local/share/acme.sh/    # Native acme.sh (on DSM host)
```

## Important Commands

```bash
# Install native acme.sh (one-time setup)
sudo ./scripts/install-acme-native.sh

# Issue certificate (Docker)
./scripts/issue-cert.sh

# Deploy to DSM (native acme.sh)
sudo ./scripts/deploy-to-dsm.sh

# Renew certificate (checks if needed, Docker + native)
sudo ./scripts/renew-cert.sh

# Force renewal
sudo ./scripts/renew-cert.sh --force

# Check certificate expiration
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -dates

# View logs
tail -f logs/renewal.log
tail -f logs/acme-native.log

# Restart Docker container
docker-compose restart

# View container logs
docker-compose logs -f
```

## Support

- Full documentation: [README.md](README.md)
- Architecture: [plan.md](plan.md)
- acme.sh docs: https://github.com/acmesh-official/acme.sh
- dynv6 docs: https://dynv6.com/docs/apis

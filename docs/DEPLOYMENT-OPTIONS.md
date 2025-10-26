# Certificate Deployment Options

This document describes the different methods available for deploying Let's Encrypt certificates to your Synology DSM system.

## Overview

There are two primary deployment approaches:

1. **Native Deployment** (Recommended) - Uses acme.sh's built-in `--deploy-hook` mechanism
2. **Manual Deployment** - Uses standalone deployment scripts for more control

## Native Deployment (Recommended)

### How It Works

The native deployment method leverages acme.sh's built-in deployment hook system. When a certificate is issued or renewed, acme.sh automatically triggers the deployment script.

### Advantages

- **Automatic**: Deployment happens automatically during certificate renewal
- **Integrated**: Uses acme.sh's native deployment hook mechanism
- **Reliable**: Follows acme.sh's standard deployment patterns
- **Simpler**: No need to remember to run separate deployment commands

### Setup

1. Install acme.sh natively on your Synology:
   ```bash
   ./scripts/install-acme-native.sh
   ```

2. Configure your environment in `.env`:
   ```bash
   DOMAIN=example.com
   SYNOLOGY_USERNAME=admin
   SYNOLOGY_PASSWORD=your_password
   # Optional: SYNOLOGY_CERTIFICATE=your_cert_description
   # Optional: SYNOLOGY_CREATE=1
   ```

3. Issue your first certificate:
   ```bash
   ./scripts/renew-cert.sh
   ```

### How Deployment Works

When you run `renew-cert.sh`:

1. acme.sh issues/renews the certificate using your configured DNS provider
2. Automatically triggers the deployment hook (`--deploy-hook synology_dsm`)
3. Deploys the certificate to DSM using the Synology API
4. Restarts nginx if needed to activate the new certificate

### Deployment Hook Configuration

The deployment is configured via environment variables:

```bash
# Required
export SYNO_Username='admin'
export SYNO_Password='your_password'

# Optional
export SYNO_Certificate='Description for this cert'  # Default: domain name
export SYNO_Create=1                                  # Create new cert if not found
```

These are automatically set from your `.env` file by `renew-cert.sh`.

### Certificate Management

To view installed certificates on your DSM:
```bash
ssh admin@your-nas
sudo /usr/syno/bin/synow3tool --list-cert
```

### Troubleshooting

**Certificate not deploying automatically:**
- Check that `--deploy-hook synology_dsm` is in your acme.sh command
- Verify your DSM credentials in `.env`
- Check acme.sh logs: `~/.acme.sh/acme.sh.log`

**Wrong certificate being updated:**
- Set `SYNOLOGY_CERTIFICATE` in `.env` to match the exact description in DSM
- Use `SYNOLOGY_CREATE=1` to create a new certificate instead

**Deployment fails with API errors:**
- Verify DSM username has admin privileges
- Check that DSM web interface is accessible
- Ensure firewall isn't blocking port 5000/5001

## Manual Deployment

### How It Works

The manual deployment method uses a standalone script (`deploy-to-dsm.sh`) that you run separately after certificate renewal.

### Advantages

- **Control**: Run deployment when you want
- **Testing**: Useful for testing certificate changes before deployment
- **Flexibility**: Can deploy certificates from any location
- **Debugging**: Easier to debug deployment issues

### Setup

1. Configure your environment in `.env`:
   ```bash
   DOMAIN=example.com
   SYNOLOGY_USERNAME=admin
   SYNOLOGY_PASSWORD=your_password
   # Optional: SYNOLOGY_CERTIFICATE=your_cert_description
   # Optional: SYNOLOGY_CREATE=1
   ```

2. Ensure certificates exist in `~/.acme.sh/your.domain/`

3. Run the deployment script:
   ```bash
   ./scripts/deploy-to-dsm.sh
   ```

### Workflow

1. Issue/renew certificate (without deployment hook):
   ```bash
   acme.sh --issue --dns dns_cf -d example.com
   ```

2. Deploy manually when ready:
   ```bash
   ./scripts/deploy-to-dsm.sh
   ```

### Use Cases

**When to use manual deployment:**

- Testing certificate changes before production deployment
- Deploying certificates from a different machine
- Need to coordinate deployment with other maintenance tasks
- Troubleshooting deployment issues
- Using custom certificate sources

### Deployment Options

The `deploy-to-dsm.sh` script supports several options:

```bash
# Deploy using settings from .env
./scripts/deploy-to-dsm.sh

# Deploy specific certificate
DOMAIN=example.com ./scripts/deploy-to-dsm.sh

# Deploy with custom description
SYNOLOGY_CERTIFICATE="My Custom Cert" ./scripts/deploy-to-dsm.sh

# Deploy and create new certificate in DSM
SYNOLOGY_CREATE=1 ./scripts/deploy-to-dsm.sh
```

### Scheduling Manual Deployment

If using manual deployment with cron, create a wrapper script:

```bash
#!/bin/bash
# /home/your_user/renew-and-deploy.sh

cd /path/to/synology-acme

# Renew certificate
./scripts/renew-cert.sh

# Deploy manually (if not using deployment hooks)
./scripts/deploy-to-dsm.sh
```

Then schedule it:
```bash
0 2 * * 0 /home/your_user/renew-and-deploy.sh
```

## Comparison

| Feature | Native Deployment | Manual Deployment |
|---------|------------------|-------------------|
| Automation | Automatic with renewal | Requires separate command |
| Setup Complexity | Simple | Simple |
| Control | Limited | Full control |
| Best For | Production use | Testing, debugging |
| Error Recovery | Automatic retry | Manual retry |
| Scheduling | Built into acme.sh | Requires separate cron |

## Migration Between Methods

### From Manual to Native

1. Ensure you have native acme.sh installed
2. Update `renew-cert.sh` to include `--deploy-hook synology_dsm`
3. Test with a renewal:
   ```bash
   ./scripts/renew-cert.sh --force
   ```

### From Native to Manual

1. Remove `--deploy-hook synology_dsm` from your renewal commands
2. Add manual deployment to your workflow:
   ```bash
   ./scripts/renew-cert.sh
   ./scripts/deploy-to-dsm.sh
   ```

## Best Practices

### For Native Deployment

1. **Test first**: Use `--force` to test the complete renewal and deployment:
   ```bash
   ./scripts/renew-cert.sh --force
   ```

2. **Monitor logs**: Check `~/.acme.sh/acme.sh.log` for deployment issues

3. **Set certificate description**: Use `SYNOLOGY_CERTIFICATE` to manage multiple certificates

4. **Enable creation**: Use `SYNOLOGY_CREATE=1` for first-time setup

### For Manual Deployment

1. **Test deployment separately**: Test `deploy-to-dsm.sh` before adding to automation

2. **Use error handling**: Check exit codes and log output

3. **Coordinate timing**: Schedule deployments during maintenance windows

4. **Keep backups**: DSM maintains certificate backups, but verify before major changes

## Security Considerations

### Credential Storage

Both methods require storing DSM credentials in `.env`:

```bash
# Restrict permissions
chmod 600 .env

# Consider using a dedicated DSM user with minimal permissions:
# - Create a user specifically for certificate deployment
# - Grant only necessary permissions
# - Rotate password regularly
```

### SSH Access

If running from a different machine:

```bash
# Use SSH keys instead of passwords
ssh-copy-id admin@your-nas

# Restrict SSH key usage
# Add this to ~/.ssh/authorized_keys on NAS:
# command="/usr/local/bin/deploy-only.sh" ssh-rsa AAAA...
```

### Network Security

```bash
# Use HTTPS for DSM API (port 5001)
# Enable 2FA for admin account
# Restrict API access to specific IPs if possible
# Monitor DSM logs for unauthorized access
```

## Troubleshooting

### Common Issues

**Certificate deployed but not active:**
```bash
# DSM may need nginx restart
# This usually happens automatically, but if not:
ssh admin@your-nas
sudo synosystemctl restart nginx
```

**Multiple certificates with same domain:**
```bash
# List all certificates
ssh admin@your-nas
sudo /usr/syno/bin/synow3tool --list-cert

# Use SYNOLOGY_CERTIFICATE to specify which one to update
export SYNOLOGY_CERTIFICATE="exact description from list"
```

**Deployment fails with permission errors:**
```bash
# Verify user has admin privileges
# Check DSM User & Group settings
# Ensure user isn't locked out
```

### Debug Mode

Enable verbose logging:

```bash
# For native deployment
export DEBUG=1
./scripts/renew-cert.sh --force

# For manual deployment
export DEBUG=1
./scripts/deploy-to-dsm.sh
```

### Getting Help

1. Check acme.sh logs: `~/.acme.sh/acme.sh.log`
2. Check DSM system logs: Control Panel > Log Center
3. Enable debug mode for detailed output
4. Review this documentation and README.md
5. Check acme.sh wiki: https://github.com/acmesh-official/acme.sh/wiki

## Additional Resources

- [Synology DSM API Documentation](https://github.com/acmesh-official/acme.sh/wiki/deployhooks#20-deploy-the-cert-into-synology-dsm)
- [acme.sh Documentation](https://github.com/acmesh-official/acme.sh)
- [Let's Encrypt Best Practices](https://letsencrypt.org/docs/)

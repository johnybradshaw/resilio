# Linode Object Storage Setup for Resilio Backups

## Overview

This guide explains how to configure Linode Object Storage for automated Resilio Sync backups.

## Prerequisites

- Linode account with Object Storage enabled
- Access to Linode Cloud Manager

## Step 1: Create Object Storage Bucket

### Via Linode Cloud Manager

1. Log in to [Linode Cloud Manager](https://cloud.linode.com)
2. Navigate to **Object Storage** in the left sidebar
3. Click **Create Bucket**
4. Configure:
   - **Label**: `resilio-backups` (or custom name)
   - **Region**: Choose same or nearby region as your instances
   - **Access**: Leave as private
5. Click **Create Bucket**

### Via Linode CLI

```bash
linode-cli object-storage buckets create \
  --cluster us-east-1 \
  --label resilio-backups
```

## Step 2: Generate Access Keys

### Via Linode Cloud Manager

1. In **Object Storage**, go to **Access Keys**
2. Click **Create Access Key**
3. Configure:
   - **Label**: `resilio-backup-key`
   - **Access**: Limited (select your bucket)
4. Click **Create Access Key**
5. **IMPORTANT**: Copy both the **Access Key** and **Secret Key** immediately
   - Secret key is shown only once
   - Store securely (e.g., 1Password, password manager)

### Via Linode CLI

```bash
linode-cli object-storage keys create \
  --label resilio-backup-key
```

## Step 3: Configure Terraform Variables

Edit your `terraform.tfvars`:

```hcl
# Object Storage credentials
object_storage_access_key = "YOUR_ACCESS_KEY_HERE"
object_storage_secret_key = "YOUR_SECRET_KEY_HERE"

# Object Storage configuration
object_storage_endpoint = "us-east-1.linodeobjects.com"  # Match your bucket region
object_storage_bucket   = "resilio-backups"               # Your bucket name
```

### Available Endpoints by Region

| Region | Endpoint |
|--------|----------|
| Newark, NJ | `us-east-1.linodeobjects.com` |
| Atlanta, GA | `us-southeast-1.linodeobjects.com` |
| Frankfurt, DE | `eu-central-1.linodeobjects.com` |
| Singapore | `ap-south-1.linodeobjects.com` |

## Step 4: Apply Terraform Configuration

```bash
terraform plan
terraform apply
```

## Backup Behavior

### Automatic Backups

- **Schedule**: Daily at 2:00 AM (server local time)
- **Method**: Incremental sync (only changed files)
- **Retention**: 30 days (older backups automatically deleted)
- **Location**: `<bucket>/<hostname>/`
  - Example: `resilio-backups/resilio-sync-us-east-a1b2c3d4.example.com/`

### What Gets Backed Up

- ✅ All Resilio Sync data in `/mnt/resilio-data/`
- ✅ Resilio configuration in `.sync/`
- ❌ Temporary sync files (`.sync/StreamsList`, `*.!sync`)
- ❌ Download state files (`.sync/DownloadState`)

### Backup Logs

View backup logs on each instance:

```bash
# Via jumpbox
ssh -J ac-user@jumpbox.example.com ac-user@resilio-sync-us-east.example.com

# View backup log
sudo tail -f /var/log/resilio-backup.log

# View last backup
sudo tail -20 /var/log/resilio-backup.log
```

## Manual Backup

To trigger a backup manually:

```bash
sudo /usr/local/bin/resilio-backup.sh
```

## Restore from Backup

### Full Restore

If you need to restore all data:

```bash
# Stop Resilio Sync
sudo systemctl stop resilio-sync

# Restore from Object Storage
rclone sync r:resilio-backups/<hostname>/ /mnt/resilio-data/ \
  --progress \
  --log-file=/var/log/resilio-restore.log

# Fix permissions
sudo chown -R rslsync:rslsync /mnt/resilio-data

# Restart Resilio Sync
sudo systemctl start resilio-sync
```

### Selective Restore

To restore specific files or folders:

```bash
# List available backups
rclone ls r:resilio-backups/<hostname>/

# Restore specific folder
rclone copy r:resilio-backups/<hostname>/<folder-key>/ \
  /mnt/resilio-data/<folder-key>/ \
  --progress
```

## Verify Backups

### Check Backup Exists

```bash
# List all backups
rclone ls r:resilio-backups/

# List specific host backup
rclone ls r:resilio-backups/resilio-sync-us-east-a1b2c3d4.example.com/

# Check backup size
rclone size r:resilio-backups/resilio-sync-us-east-a1b2c3d4.example.com/
```

### Test Restore

Periodically test restoring to a temporary location:

```bash
# Test restore to /tmp
rclone sync r:resilio-backups/<hostname>/ /tmp/restore-test/ \
  --dry-run  # Remove --dry-run to actually restore

# Verify files
ls -lah /tmp/restore-test/
```

## Cost Management

### Estimate Storage Costs

Linode Object Storage pricing (as of 2024):
- **Storage**: $0.02/GB per month
- **Outbound Transfer**: $0.005/GB (inbound free)

Example monthly costs:
- 100 GB data: ~$2/month
- 500 GB data: ~$10/month
- 1 TB data: ~$20/month

### Monitor Usage

```bash
# Check bucket size
rclone size r:resilio-backups/

# Check per-host size
for host in $(rclone lsd r:resilio-backups/ | awk '{print $5}'); do
  echo "Host: $host"
  rclone size r:resilio-backups/$host/
done
```

## Troubleshooting

### Backup Not Running

1. **Check cron is configured**:
   ```bash
   sudo crontab -l | grep resilio-backup
   ```

2. **Check credentials**:
   ```bash
   rclone listremotes
   # Should show: r:
   ```

3. **Test rclone connection**:
   ```bash
   rclone lsd r:
   # Should list your bucket
   ```

4. **Check backup log**:
   ```bash
   sudo tail -50 /var/log/resilio-backup.log
   ```

### Permission Denied

```bash
# Fix rclone config permissions
sudo chmod 600 /root/.config/rclone/rclone.conf

# Verify credentials
cat /root/.config/rclone/rclone.conf
```

### Backup Taking Too Long

Adjust backup script settings in `/usr/local/bin/resilio-backup.sh`:

```bash
# Increase transfers and checkers for faster backups
rclone sync "$BACKUP_SOURCE" "$BACKUP_DEST" \
  --transfers 16 \     # Increase from 8
  --checkers 32 \      # Increase from 16
  --log-file="$LOG_FILE"
```

## Security Best Practices

1. **Limit Access Key Permissions**
   - Use bucket-specific access keys (not account-wide)
   - Grant minimum required permissions (read/write on specific bucket)

2. **Rotate Keys Regularly**
   - Generate new access keys every 90 days
   - Update `terraform.tfvars` and reapply

3. **Enable Bucket Versioning** (if available)
   - Protects against accidental deletion
   - Allows recovery of previous versions

4. **Monitor Access Logs**
   - Review Object Storage access logs periodically
   - Alert on unusual activity

## Disable Backups

To disable backups without removing configuration:

```bash
# Remove cron job
sudo crontab -r

# Or edit terraform.tfvars
object_storage_access_key = "CHANGEME"
terraform apply
```

## Additional Resources

- [Linode Object Storage Documentation](https://www.linode.com/docs/products/storage/object-storage/)
- [rclone Documentation](https://rclone.org/s3/)
- [Object Storage Pricing](https://www.linode.com/pricing/#object-storage)

---

**Last Updated**: 2024

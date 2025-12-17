# Volume Resize Safety Guide

## Overview

This guide explains how to safely resize Resilio Sync storage volumes without risking data loss or system downtime.

## Safety Mechanisms in Place

### 1. **Prevent Accidental Deletion**
```hcl
lifecycle {
  prevent_destroy = true
}
```
- Volumes cannot be accidentally deleted via Terraform
- Any attempt to destroy a volume will fail with an error
- To intentionally delete: remove this rule, then apply

### 2. **Prevent Recreate on Label/Region Changes**
```hcl
lifecycle {
  ignore_changes = [label, region]
}
```
- Changing volume labels or regions won't trigger recreation
- Ensures volumes are never destroyed and recreated (which would lose data)
- Volumes persist even if naming conventions change

### 3. **Size Validation**
```hcl
validation {
  condition     = var.volume_size >= 10 && var.volume_size <= 10000
  error_message = "Volume size must be between 10 and 10000 GB."
}
```
- Prevents invalid sizes (too small or too large)
- Linode volumes: minimum 10 GB, maximum 10,000 GB

## Safe Resize Process

### ⚠️ CRITICAL: Volumes Can Only Be EXPANDED (Never Shrunk)

Linode block storage volumes **cannot be shrunk**. Attempting to decrease size will require:
1. Creating a new smaller volume
2. Manually copying data
3. Reattaching the new volume
4. **This process involves downtime and risk**

**Always plan for growth. It's safer to start larger than to need to shrink later.**

---

## How to Safely Resize a Volume

### Step 1: Update Terraform Variables

Edit your `terraform.tfvars`:

```hcl
volume_size = 50  # Increase from current size (e.g., 20 GB → 50 GB)
```

**Important**: Only increase the size. Never decrease.

### Step 2: Plan the Changes

```bash
terraform plan
```

**Expected output**:
```
# module.storage_volumes["us-east"].linode_volume.storage will be updated in-place
~ resource "linode_volume" "storage" {
    ~ size = 20 -> 50
  }
```

**Verify**:
- ✅ Shows "will be updated in-place"
- ✅ Only the `size` attribute changes
- ❌ **STOP** if it shows "must be replaced" or "will be destroyed"

### Step 3: Apply the Changes

```bash
terraform apply
```

This will:
- Expand the volume online (no detach required)
- Complete in seconds to minutes depending on size
- **No downtime** for the Resilio Sync service

### Step 4: Resize the Filesystem

**Terraform only resizes the volume**, not the filesystem. You must manually resize:

#### SSH into Each Affected Instance

```bash
# Via jumpbox
ssh -J ac-user@jumpbox.example.com ac-user@resilio-sync-us-east.example.com
```

#### Resize the ext4 Filesystem

```bash
# Check current filesystem size
df -h /mnt/resilio-data

# Resize filesystem to use all available space (online, no unmount needed)
sudo resize2fs /dev/disk/by-label/resilio

# Verify new size
df -h /mnt/resilio-data
```

**Example output**:
```
Before: /dev/sdc1       20G   15G  5.0G  75% /mnt/resilio-data
After:  /dev/sdc1       50G   15G   35G  30% /mnt/resilio-data
```

#### Verify Resilio Sync is Healthy

```bash
# Check Resilio Sync status
sudo systemctl status resilio-sync

# Check logs for any issues
sudo journalctl -u resilio-sync -n 50

# Verify sync is active
ls -lah /mnt/resilio-data
```

---

## Emergency Rollback (If Something Goes Wrong)

### If Terraform Apply Fails

1. **Do NOT panic**
   - Volume data is safe (lifecycle prevents destruction)
   - Linode volumes persist independently of Terraform state

2. **Check Linode Console**
   ```bash
   # Verify volume exists and size
   linode-cli volumes list
   ```

3. **Revert terraform.tfvars**
   ```hcl
   volume_size = 20  # Back to original size
   ```

4. **Import existing volume** (if state is corrupted)
   ```bash
   terraform import 'module.storage_volumes["us-east"].linode_volume.storage' <volume-id>
   ```

### If Filesystem Resize Fails

1. **Filesystem is still safe** (resize2fs doesn't destroy data)

2. **Check for errors**
   ```bash
   # Check filesystem integrity
   sudo e2fsck -f /dev/disk/by-label/resilio

   # Retry resize
   sudo resize2fs /dev/disk/by-label/resilio
   ```

3. **Manual resize (if automatic fails)**
   ```bash
   # Get exact block size
   sudo tune2fs -l /dev/disk/by-label/resilio | grep 'Block count'

   # Resize to specific size (in blocks)
   sudo resize2fs /dev/disk/by-label/resilio <new-block-count>
   ```

---

## Monitoring Volume Usage

### Set Up Alerts

Add monitoring to prevent running out of space:

```bash
# Check current usage
df -h /mnt/resilio-data

# Set up ncdu for detailed analysis
sudo ncdu /mnt/resilio-data
```

### Recommended Thresholds

- **Warning**: 70% full → Plan resize
- **Critical**: 85% full → Resize immediately
- **Emergency**: 95% full → Urgent intervention needed

### Automated Monitoring Script

Add to cron (runs daily at 6 AM):

```bash
# /usr/local/bin/check-volume-usage.sh
#!/bin/bash
THRESHOLD=70
USAGE=$(df /mnt/resilio-data | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$USAGE" -ge "$THRESHOLD" ]; then
  echo "WARNING: Volume usage at ${USAGE}% (threshold: ${THRESHOLD}%)"
  echo "Consider resizing the volume."
fi
```

---

## Best Practices

### 1. **Plan for Growth**
- Estimate 6-12 months of data growth
- Add 20% buffer for unexpected growth
- Resize proactively before hitting 70% usage

### 2. **Test Resize in Non-Production First**
- If possible, test the resize process on a test instance
- Document your specific resize times and procedures

### 3. **Backup Before Major Resizes**
- While resize is safe, backups provide extra insurance
- Verify Object Storage backups are up to date
- Consider manual snapshot before resize

### 4. **Schedule During Low-Activity Periods**
- Filesystem resize is online but may cause brief I/O pauses
- Schedule during maintenance windows if possible
- Inform users of potential brief slowdowns

### 5. **Document Your Resize**
- Record original size, new size, and date
- Note any issues encountered
- Update capacity planning documents

---

## FAQ

### Q: Can I resize without downtime?
**A:** Yes! Both volume expansion and `resize2fs` work online without unmounting.

### Q: How long does resize take?
**A:**
- Terraform volume expansion: 10 seconds to 2 minutes
- Filesystem resize: Seconds for small volumes, minutes for very large ones

### Q: What if I need to shrink a volume?
**A:** This requires:
1. Creating a new smaller volume
2. Stopping Resilio Sync
3. Copying data to new volume
4. Updating Terraform to use new volume
5. Restarting services
**This is complex and risky. Avoid if possible.**

### Q: Will resize affect my data?
**A:** No. Volume expansion is non-destructive. Data remains intact.

### Q: Can I automate filesystem resize?
**A:** Yes, but not recommended. Manual verification ensures safety. You could add a cloud-init script that runs `resize2fs` on boot, but this may mask issues.

### Q: What if resize fails mid-operation?
**A:** Very rare. Linode volumes are expanded atomically. If Terraform fails, the volume state is consistent. Filesystem resize is also safe and can be retried.

---

## Additional Resources

- [Linode Block Storage Documentation](https://www.linode.com/docs/products/storage/block-storage/)
- [resize2fs Manual](https://man7.org/linux/man-pages/man8/resize2fs.8.html)
- [Terraform Lifecycle Meta-Arguments](https://www.terraform.io/docs/language/meta-arguments/lifecycle.html)

---

## Support

If you encounter issues during resize:

1. Check logs: `sudo journalctl -u resilio-sync -n 100`
2. Verify volume: `lsblk` and `df -h`
3. Check Terraform state: `terraform show`
4. Review Linode Console for volume status

For emergency support, preserve:
- Terraform plan/apply output
- System logs (`journalctl`)
- Volume and filesystem status (`df`, `lsblk`, `mount`)

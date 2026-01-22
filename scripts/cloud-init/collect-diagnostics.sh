#!/bin/bash
# Collect all diagnostic logs for troubleshooting cloud-init and system issues
set -e

DIAG_DIR="/tmp/diagnostics-$(date +%Y%m%d-%H%M%S)"
DIAG_TAR="$DIAG_DIR.tar.gz"

echo "=== Collecting diagnostics to $DIAG_DIR ==="
mkdir -p "$DIAG_DIR"

# Cloud-init logs
echo "Collecting cloud-init logs..."
cp /var/log/cloud-init.log "$DIAG_DIR/" 2>/dev/null || true
cp /var/log/cloud-init-output.log "$DIAG_DIR/" 2>/dev/null || true
cloud-init status --long > "$DIAG_DIR/cloud-init-status.txt" 2>&1 || true
cloud-init analyze show > "$DIAG_DIR/cloud-init-analyze.txt" 2>&1 || true
cloud-init analyze blame > "$DIAG_DIR/cloud-init-blame.txt" 2>&1 || true

# System logs
echo "Collecting system logs..."
journalctl -b --no-pager > "$DIAG_DIR/journalctl-boot.log" 2>&1 || true
journalctl -u cloud-init --no-pager > "$DIAG_DIR/journalctl-cloud-init.log" 2>&1 || true
journalctl -u cloud-final --no-pager > "$DIAG_DIR/journalctl-cloud-final.log" 2>&1 || true
dmesg > "$DIAG_DIR/dmesg.log" 2>&1 || true

# Custom application logs
echo "Collecting application logs..."
cp /var/log/volume-expand.log "$DIAG_DIR/" 2>/dev/null || true
cp /var/log/resilio-backup.log "$DIAG_DIR/" 2>/dev/null || true
journalctl -u resilio-sync --no-pager > "$DIAG_DIR/journalctl-resilio-sync.log" 2>&1 || true
journalctl -u volume-auto-expand --no-pager > "$DIAG_DIR/journalctl-volume-expand.log" 2>&1 || true

# Disk and mount information
echo "Collecting disk/mount info..."
lsblk -f > "$DIAG_DIR/lsblk.txt" 2>&1 || true
blkid > "$DIAG_DIR/blkid.txt" 2>&1 || true
df -h > "$DIAG_DIR/df.txt" 2>&1 || true
mount > "$DIAG_DIR/mount.txt" 2>&1 || true
cat /etc/fstab > "$DIAG_DIR/fstab.txt" 2>/dev/null || true
cat /etc/resilio-sync/folder-device-map.json > "$DIAG_DIR/folder-device-map.json" 2>/dev/null || true

# Service status
echo "Collecting service status..."
systemctl status resilio-sync > "$DIAG_DIR/status-resilio-sync.txt" 2>&1 || true
systemctl status cloud-init > "$DIAG_DIR/status-cloud-init.txt" 2>&1 || true
systemctl status cloud-final > "$DIAG_DIR/status-cloud-final.txt" 2>&1 || true
systemctl status volume-auto-expand > "$DIAG_DIR/status-volume-expand.txt" 2>&1 || true
systemctl list-units --failed > "$DIAG_DIR/failed-units.txt" 2>&1 || true

# Configuration files (sanitized)
echo "Collecting configuration..."
cat /etc/resilio-sync/config.json | jq 'del(.shared_folders[].secret)' > "$DIAG_DIR/resilio-config-sanitized.json" 2>/dev/null || true

# System info
echo "Collecting system info..."
uname -a > "$DIAG_DIR/uname.txt" 2>&1 || true
hostname -f > "$DIAG_DIR/hostname.txt" 2>&1 || true
cat /etc/os-release > "$DIAG_DIR/os-release.txt" 2>/dev/null || true
free -h > "$DIAG_DIR/memory.txt" 2>&1 || true

# Create tarball
echo "Creating tarball..."
tar -czf "$DIAG_TAR" -C /tmp "$(basename $DIAG_DIR)"
rm -rf "$DIAG_DIR"

echo ""
echo "=== Diagnostics collected ==="
echo "File: $DIAG_TAR"
echo "Size: $(du -h $DIAG_TAR | cut -f1)"
echo ""
echo "To download via SSH:"
echo "  scp -J ac-user@<jumpbox> ac-user@$(hostname -f):$DIAG_TAR ."
echo ""
echo "Or view directly:"
echo "  tar -tzf $DIAG_TAR"

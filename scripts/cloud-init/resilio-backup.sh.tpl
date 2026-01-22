#!/bin/bash
# Enhanced backup script - supports versioning, multi-region, and smart scheduling
set -euo pipefail

# Configuration
CONFIG_FILE="/etc/resilio-sync/backup-config.json"
DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
BASE_MOUNT="${base_mount_point}"
LOG_FILE="/var/log/resilio-backup.log"
LOCK_FILE="/var/run/resilio-backup.lock"

# Read config
if [ -f "$CONFIG_FILE" ]; then
  TRANSFERS=$(jq -r '.transfers // 8' "$CONFIG_FILE")
  BANDWIDTH=$(jq -r '.bandwidth_limit // ""' "$CONFIG_FILE")
  RETENTION_DAYS=$(jq -r '.retention_days // 90' "$CONFIG_FILE")
  VERSIONING=$(jq -r '.versioning // true' "$CONFIG_FILE")
else
  TRANSFERS=8
  BANDWIDTH=""
  RETENTION_DAYS=90
  VERSIONING=true
fi

# Build rclone options
RCLONE_OPTS="--transfers $TRANSFERS --log-file=$LOG_FILE --log-level INFO"
RCLONE_OPTS="$RCLONE_OPTS --exclude '.sync/StreamsList' --exclude '.sync/DownloadState' --exclude '*.!sync'"
[ -n "$BANDWIDTH" ] && RCLONE_OPTS="$RCLONE_OPTS --bwlimit $BANDWIDTH"

# Logging helper
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Acquire lock to prevent concurrent backups
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "Another backup is already running, exiting"
  exit 0
fi

# Get hostname for backup path
HOSTNAME=$(hostname -f)

log "=== Starting backup ==="
log "Host: $HOSTNAME"
log "Transfers: $TRANSFERS, Bandwidth: $${BANDWIDTH:-unlimited}"
log "Versioning: $VERSIONING, Retention: $RETENTION_DAYS days"

# Get list of rclone remotes (backup destinations)
REMOTES=$(rclone listremotes 2>/dev/null | grep -E '^(r|backup-)' || echo "r:")

# Determine sync command based on versioning
if [ "$VERSIONING" = "true" ]; then
  SYNC_CMD="copy"  # Use copy to preserve versions
  log "Using copy mode (versioning enabled)"
else
  SYNC_CMD="sync"  # Use sync for exact mirror
  log "Using sync mode (versioning disabled)"
fi

ERRORS=0

# Backup each folder
if [ -f "$DEVICE_MAP" ]; then
  FOLDERS=$(jq -r 'to_entries[] | "\(.key)|\(.value.mount_point)"' "$DEVICE_MAP")
else
  # Fallback to single base mount
  FOLDERS="data|$BASE_MOUNT"
fi

echo "$FOLDERS" | while IFS='|' read -r FOLDER_NAME MOUNT_POINT; do
  [ -z "$FOLDER_NAME" ] && continue

  log "Backing up folder: $FOLDER_NAME from $MOUNT_POINT"

  # Backup to each remote
  for REMOTE in $REMOTES; do
    REMOTE_NAME=$(echo "$REMOTE" | tr -d ':')
    BUCKET=$(rclone config show "$REMOTE_NAME" 2>/dev/null | grep -E '^bucket' | cut -d= -f2 | tr -d ' ' || echo "${object_storage_bucket}")
    [ -z "$BUCKET" ] && BUCKET="${object_storage_bucket}"

    DEST="$REMOTE$BUCKET/$HOSTNAME/$FOLDER_NAME"
    log "  -> $DEST"

    if eval rclone $SYNC_CMD "$MOUNT_POINT" "$DEST" $RCLONE_OPTS; then
      log "  Backup complete to $REMOTE_NAME"
    else
      log "  ERROR: Backup failed to $REMOTE_NAME"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

# Cleanup old versions (only if retention is set)
if [ "$RETENTION_DAYS" -gt 0 ]; then
  log "Cleaning up files older than $RETENTION_DAYS days..."
  for REMOTE in $REMOTES; do
    REMOTE_NAME=$(echo "$REMOTE" | tr -d ':')
    BUCKET=$(rclone config show "$REMOTE_NAME" 2>/dev/null | grep -E '^bucket' | cut -d= -f2 | tr -d ' ' || echo "${object_storage_bucket}")
    [ -z "$BUCKET" ] && BUCKET="${object_storage_bucket}"

    rclone delete "$REMOTE$BUCKET/$HOSTNAME" --min-age "$${RETENTION_DAYS}d" >> "$LOG_FILE" 2>&1 || true
  done
fi

log "=== Backup complete (errors: $ERRORS) ==="
exit $ERRORS

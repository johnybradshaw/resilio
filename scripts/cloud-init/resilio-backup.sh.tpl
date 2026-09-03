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

# --- Backup health -----------------------------------------------------------
# Backups failed silently for 222 days: the configured endpoint did not resolve,
# and nothing recorded whether a backup had ever succeeded. Both are now loud.
STAMP_FILE="/var/lib/resilio-backup/last-success"
STALE_AFTER_DAYS=2
mkdir -p "$(dirname "$STAMP_FILE")"

check_staleness() {
  local last age
  if [ ! -f "$STAMP_FILE" ]; then
    log "WARNING: no successful backup has ever been recorded on this host"
    return 0
  fi
  last=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - last ) / 86400 ))
  if [ "$age" -ge "$STALE_AFTER_DAYS" ]; then
    log "ERROR: last successful backup was $age days ago (threshold $STALE_AFTER_DAYS)"
    return 1
  fi
  log "Last successful backup: $age day(s) ago"
  return 0
}

# Refuse to transfer to an endpoint that does not resolve. This is the exact
# failure that went unnoticed: rclone was pointed at "us-east.linodeobjects.com"
# (the compute region id) instead of "us-east-1.linodeobjects.com".
# Uses rclone itself rather than a DNS lookup: one call exercises name
# resolution, TLS, credentials and bucket access. A DNS-only check would have
# caught the original bug but says nothing about a revoked or misscoped key -
# and the key IS replaced whenever the buckets change.
preflight_remotes() {
  local bad=0 name ep
  for R in $REMOTES; do
    name=$(echo "$R" | tr -d ':')
    ep=$(rclone config show "$name" 2>/dev/null | awk -F'= *' '/^endpoint/{print $2; exit}')
    if rclone lsd "$R" --max-depth 1 --retries 1 --low-level-retries 1 \
         --timeout 30s --contimeout 15s >/dev/null 2>&1; then
      log "Preflight OK for remote '$name' ($ep)"
    else
      log "ERROR: remote '$name' unreachable - check DNS, endpoint, credentials or bucket ($ep)"
      bad=$((bad + 1))
    fi
  done
  return $bad
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

# Get list of rclone remotes (backup destinations).
# Previously this fell back to a bare "r:" when nothing was configured, so a
# missing rclone config looked like a working backup. Fail instead.
if [ -z "$(rclone listremotes 2>/dev/null)" ]; then
  log "ERROR: no rclone remotes configured - cannot back up. Aborting."
  exit 1
fi
# `|| true`: with `set -e`, a non-matching grep returns 1 and would abort here,
# before the explicit check below could log WHY nothing matched.
REMOTES=$(rclone listremotes 2>/dev/null | grep -E '^(r|backup-)' || true)
if [ -z "$REMOTES" ]; then
  log "ERROR: rclone has remotes but none match the expected backup naming. Aborting."
  exit 1
fi

check_staleness || true   # reports loudly; does not block this run

if ! preflight_remotes; then
  log "ERROR: aborting - one or more backup endpoints are unreachable"
  exit 1
fi

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

# NOTE: fed by here-string, NOT `echo "$FOLDERS" | while`. A pipeline runs the
# loop in a subshell, so every ERRORS increment inside it is discarded and the
# parent sees 0 - which would write a success stamp after a totally failed run
# and make the staleness check below report healthy. Do not reintroduce a pipe.
while IFS='|' read -r FOLDER_NAME MOUNT_POINT; do
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
done <<< "$FOLDERS"

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

if [ "$ERRORS" -eq 0 ]; then
  date +%s > "$STAMP_FILE"
  log "Success stamp updated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
else
  log "ERROR: $ERRORS backup(s) failed - success stamp deliberately NOT updated"
fi

log "=== Backup complete (errors: $ERRORS) ==="
exit $ERRORS

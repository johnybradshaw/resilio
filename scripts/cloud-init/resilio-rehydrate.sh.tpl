#!/bin/bash
# Rehydration script - restore from backup to new/rebuilt VMs
set -euo pipefail

# Configuration
DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
BASE_MOUNT="${base_mount_point}"
LOG_FILE="/var/log/resilio-rehydrate.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Restore data from Object Storage backup to this VM."
  echo "Use this to quickly rehydrate a new or rebuilt VM."
  echo ""
  echo "Options:"
  echo "  -s, --source HOSTNAME   Source hostname to restore from (default: auto-detect)"
  echo "  -f, --folder NAME       Only restore specific folder (default: all)"
  echo "  -r, --remote NAME       Rclone remote to restore from (default: r:)"
  echo "  -l, --list              List available backups"
  echo "  -n, --dry-run           Show what would be restored without making changes"
  echo "  -h, --help              Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 --list                           # List available backups"
  echo "  $0                                  # Restore all folders from most recent"
  echo "  $0 --source old-server.example.com # Restore from specific host"
  echo "  $0 --folder documents              # Restore only documents folder"
  echo "  $0 --dry-run                       # Preview restore operation"
}

# Parse arguments
SOURCE_HOST=""
FOLDER_FILTER=""
REMOTE="r:"
DRY_RUN=""
LIST_ONLY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--source) SOURCE_HOST="$2"; shift 2 ;;
    -f|--folder) FOLDER_FILTER="$2"; shift 2 ;;
    -r|--remote) REMOTE="$2:"; shift 2 ;;
    -l|--list) LIST_ONLY="1"; shift ;;
    -n|--dry-run) DRY_RUN="--dry-run"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

BUCKET="${object_storage_bucket}"

# List available backups
if [ -n "$LIST_ONLY" ]; then
  log "Available backups in $REMOTE$BUCKET:"
  rclone lsd "$REMOTE$BUCKET" 2>/dev/null | awk '{print "  " $NF}'
  exit 0
fi

# Auto-detect source host if not specified
if [ -z "$SOURCE_HOST" ]; then
  # Try to find backups matching our project pattern
  AVAILABLE=$(rclone lsd "$REMOTE$BUCKET" 2>/dev/null | awk '{print $NF}' | head -1)
  if [ -z "$AVAILABLE" ]; then
    log "ERROR: No backups found in $REMOTE$BUCKET"
    log "Use --list to see available backups or --source to specify hostname"
    exit 1
  fi
  SOURCE_HOST="$AVAILABLE"
  log "Auto-detected source: $SOURCE_HOST"
fi

log "=== Starting rehydration ==="
log "Source: $REMOTE$BUCKET/$SOURCE_HOST"
log "Destination: $BASE_MOUNT"
[ -n "$DRY_RUN" ] && log "DRY RUN MODE - no changes will be made"

# Stop Resilio Sync during restore
log "Stopping Resilio Sync..."
systemctl stop resilio-sync || true

ERRORS=0

# Determine folders to restore
if [ -f "$DEVICE_MAP" ]; then
  if [ -n "$FOLDER_FILTER" ]; then
    FOLDERS="$FOLDER_FILTER|$(jq -r --arg f "$FOLDER_FILTER" '.[$f].mount_point // ""' "$DEVICE_MAP")"
  else
    FOLDERS=$(jq -r 'to_entries[] | "\(.key)|\(.value.mount_point)"' "$DEVICE_MAP")
  fi
else
  FOLDERS="data|$BASE_MOUNT"
fi

echo "$FOLDERS" | while IFS='|' read -r FOLDER_NAME MOUNT_POINT; do
  [ -z "$FOLDER_NAME" ] && continue
  [ -z "$MOUNT_POINT" ] && MOUNT_POINT="$BASE_MOUNT/$FOLDER_NAME"

  SOURCE="$REMOTE$BUCKET/$SOURCE_HOST/$FOLDER_NAME"
  log "Restoring: $SOURCE -> $MOUNT_POINT"

  # Check if source exists
  if ! rclone lsd "$SOURCE" &>/dev/null && ! rclone ls "$SOURCE" &>/dev/null 2>&1; then
    log "  WARNING: Source $SOURCE not found, skipping"
    continue
  fi

  # Ensure mount point exists
  mkdir -p "$MOUNT_POINT"

  # Restore data
  if rclone copy "$SOURCE" "$MOUNT_POINT" $DRY_RUN \
    --transfers 8 --log-file="$LOG_FILE" --log-level INFO \
    --exclude ".sync/StreamsList" --exclude ".sync/DownloadState"; then
    log "  Restore complete"
    [ -z "$DRY_RUN" ] && chown -R rslsync:rslsync "$MOUNT_POINT"
  else
    log "  ERROR: Restore failed"
    ERRORS=$((ERRORS + 1))
  fi
done

# Restart Resilio Sync
if [ -z "$DRY_RUN" ]; then
  log "Starting Resilio Sync..."
  systemctl start resilio-sync
fi

log "=== Rehydration complete (errors: $ERRORS) ==="
exit $ERRORS

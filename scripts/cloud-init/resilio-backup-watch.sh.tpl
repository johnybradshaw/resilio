#!/bin/bash
# Watches for file changes and triggers incremental backups
# Used in realtime and hybrid backup modes

CONFIG_FILE="/etc/resilio-sync/backup-config.json"
DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
BASE_MOUNT="${base_mount_point}"
LOG_FILE="/var/log/resilio-backup-watch.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if inotifywait is available
if ! command -v inotifywait &>/dev/null; then
  log "ERROR: inotifywait not found. Install inotify-tools."
  exit 1
fi

# Get folders to watch
if [ -f "$DEVICE_MAP" ]; then
  WATCH_DIRS=$(jq -r '.[] | .mount_point' "$DEVICE_MAP" | tr '\n' ' ')
else
  WATCH_DIRS="$BASE_MOUNT"
fi

log "Starting realtime backup watcher for: $WATCH_DIRS"

# Debounce: wait for changes to settle before backing up
DEBOUNCE_SECS=30
LAST_BACKUP=0

inotifywait -m -r -e modify,create,delete,move $WATCH_DIRS 2>/dev/null | while read -r DIR EVENT FILE; do
  # Skip sync metadata files
  [[ "$FILE" == *".sync"* ]] && continue
  [[ "$FILE" == *".!sync"* ]] && continue

  NOW=$(date +%s)
  ELAPSED=$((NOW - LAST_BACKUP))

  if [ $ELAPSED -ge $DEBOUNCE_SECS ]; then
    log "Change detected: $DIR$FILE ($EVENT) - triggering backup"
    /usr/local/bin/resilio-backup.sh &
    LAST_BACKUP=$NOW
  fi
done

#!/bin/bash
# Automatically expand filesystems if volumes have been resized
# Runs on boot via systemd before resilio-sync starts
# Handles multiple per-folder volumes with label-based detection
set -euo pipefail

DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
BASE_MOUNT="${base_mount_point}"
LOG="/var/log/volume-expand.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

expand_volume() {
  local DEVICE="$1"
  local PARTITION="$2"
  local LABEL="$3"
  local EXPECTED_MOUNT="$4"

  # Check if partition exists
  if [ ! -b "$PARTITION" ]; then
    log "[$LABEL] Partition $PARTITION not found, skipping"
    return 0
  fi

  # DUAL VERIFICATION: Check both label AND mount point match expected values
  # This prevents accidental expansion of wrong volumes
  ACTUAL_LABEL=$(blkid -s LABEL -o value "$PARTITION" 2>/dev/null || echo "")
  ACTUAL_MOUNT=$(findmnt -n -o TARGET "$PARTITION" 2>/dev/null || echo "")

  if [ "$ACTUAL_LABEL" != "$LABEL" ]; then
    log "[$LABEL] WARNING: Label mismatch - expected '$LABEL', found '$ACTUAL_LABEL'. Skipping."
    return 1
  fi

  if [ -n "$ACTUAL_MOUNT" ] && [ "$ACTUAL_MOUNT" != "$EXPECTED_MOUNT" ]; then
    log "[$LABEL] WARNING: Mount mismatch - expected '$EXPECTED_MOUNT', found '$ACTUAL_MOUNT'. Skipping."
    return 1
  fi

  # Verify mount point is under our base directory (safety check)
  if [[ "$EXPECTED_MOUNT" != "$BASE_MOUNT"/* ]]; then
    log "[$LABEL] WARNING: Mount point $EXPECTED_MOUNT is not under $BASE_MOUNT. Skipping."
    return 1
  fi

  # Get sizes in bytes
  DEVICE_SIZE=$(blockdev --getsize64 "$DEVICE")
  PART_SIZE=$(blockdev --getsize64 "$PARTITION")

  # Calculate difference (account for GPT overhead ~1MB)
  DIFF=$((DEVICE_SIZE - PART_SIZE))
  THRESHOLD=$((100 * 1024 * 1024))  # 100MB threshold

  if [ "$DIFF" -gt "$THRESHOLD" ]; then
    log "[$LABEL] Volume resize detected: device=$((DEVICE_SIZE/1024/1024))MB, partition=$((PART_SIZE/1024/1024))MB"
    log "[$LABEL] Expanding partition..."

    # Grow partition to fill device
    if growpart "$DEVICE" 1; then
      log "[$LABEL] Partition expanded successfully"
    else
      log "[$LABEL] ERROR: Failed to expand partition"
      return 1
    fi

    # Resize filesystem (works online for ext4)
    log "[$LABEL] Expanding filesystem..."
    if resize2fs "$PARTITION"; then
      NEW_SIZE=$(blockdev --getsize64 "$PARTITION")
      log "[$LABEL] Filesystem expanded successfully: $((NEW_SIZE/1024/1024))MB"
    else
      log "[$LABEL] ERROR: Failed to expand filesystem"
      return 1
    fi
  else
    log "[$LABEL] No expansion needed: device and partition sizes match"
  fi
}

log "Starting volume auto-expansion check..."

# Check if device map exists
if [ ! -f "$DEVICE_MAP" ]; then
  log "No device map found at $DEVICE_MAP, skipping"
  exit 0
fi

# Process each volume from the device map
ERRORS=0
jq -r 'to_entries[] | "\(.value.device_path) \(.value.partition) \(.value.label) \(.value.mount_point)"' "$DEVICE_MAP" | \
while read -r DEVICE PARTITION LABEL MOUNT; do
  if ! expand_volume "$DEVICE" "$PARTITION" "$LABEL" "$MOUNT"; then
    ERRORS=$((ERRORS + 1))
  fi
done

log "Volume auto-expansion check complete"
exit 0

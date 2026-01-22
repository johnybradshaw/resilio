#!/bin/bash
# Resilio Sync Folder Manager - allows non-destructive folder changes via SSH
# Per-folder volumes: each folder has its own volume and mount point
set -euo pipefail
BASE_MOUNT="${base_mount_point}"
FOLDERS_FILE="$BASE_MOUNT/.sync/folders.json"
DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
CONFIG_TPL="/etc/resilio-sync/config.json.tpl"
CONFIG="/etc/resilio-sync/config.json"

generate_config() {
  if [ ! -f "$FOLDERS_FILE" ]; then
    echo "Error: $FOLDERS_FILE not found" >&2
    exit 1
  fi
  # Read folders and inject into config template
  FOLDERS=$(cat "$FOLDERS_FILE")
  sed "s|FOLDERS_PLACEHOLDER|$FOLDERS|" "$CONFIG_TPL" > "$CONFIG"
  chown rslsync:rslsync "$CONFIG"
  echo "Config regenerated at $CONFIG"
}

case "$${1:-help}" in
  list)
    echo "Configured folders (from Terraform):"
    if [ -f "$DEVICE_MAP" ]; then
      jq -r 'to_entries[] | "  - \(.key): \(.value.mount_point) (\(.value.device_path))"' "$DEVICE_MAP"
    fi
    echo ""
    echo "Active Resilio folders:"
    if [ -f "$FOLDERS_FILE" ]; then
      jq -r '.[] | "  - \(.dir) [\(.secret[0:8])...]"' "$FOLDERS_FILE"
    else
      echo "  (no folders configured)"
    fi
    ;;
  add)
    if [ -z "$${2:-}" ] || [ -z "$${3:-}" ]; then
      echo "Usage: resilio-folders add <folder_key> <folder_name>"
      echo "Example: resilio-folders add BXXXXXXX... documents"
      echo ""
      echo "NOTE: For per-folder volumes, the folder must already be defined"
      echo "in Terraform (resilio_folders variable). This command adds the"
      echo "folder to Resilio's config for an existing mounted volume."
      exit 1
    fi
    KEY="$2"
    FOLDER_NAME="$3"
    FULL_PATH="$BASE_MOUNT/$FOLDER_NAME"
    # Verify mount point exists (should be pre-created by Terraform)
    if [ ! -d "$FULL_PATH" ]; then
      echo "Warning: $FULL_PATH does not exist. Creating..."
      mkdir -p "$FULL_PATH"
    fi
    chown rslsync:rslsync "$FULL_PATH"
    # Add to folders.json
    jq --arg key "$KEY" --arg dir "$FULL_PATH" \
      '. += [{"secret": $key, "dir": $dir, "use_relay_server": true, "use_tracker": true, "search_lan": false, "use_sync_trash": true, "overwrite_changes": false, "selective_sync": false}]' \
      "$FOLDERS_FILE" > "$FOLDERS_FILE.tmp" && mv "$FOLDERS_FILE.tmp" "$FOLDERS_FILE"
    chown rslsync:rslsync "$FOLDERS_FILE"
    generate_config
    echo "Added folder: $FOLDER_NAME"
    echo "Restart Resilio Sync to apply: sudo systemctl restart resilio-sync"
    ;;
  remove)
    if [ -z "$${2:-}" ]; then
      echo "Usage: resilio-folders remove <folder_name>"
      echo "Note: This removes the folder from Resilio config but keeps data"
      exit 1
    fi
    FOLDER_NAME="$2"
    FULL_PATH="$BASE_MOUNT/$FOLDER_NAME"
    jq --arg dir "$FULL_PATH" 'map(select(.dir != $dir))' \
      "$FOLDERS_FILE" > "$FOLDERS_FILE.tmp" && mv "$FOLDERS_FILE.tmp" "$FOLDERS_FILE"
    chown rslsync:rslsync "$FOLDERS_FILE"
    generate_config
    echo "Removed folder: $FOLDER_NAME (data NOT deleted)"
    echo "Restart Resilio Sync to apply: sudo systemctl restart resilio-sync"
    ;;
  status)
    echo "Volume Status:"
    if [ -f "$DEVICE_MAP" ]; then
      jq -r 'to_entries[] | .value | "\(.device_path) \(.label) \(.mount_point)"' "$DEVICE_MAP" | \
      while read -r DEV LABEL MOUNT; do
        SIZE=$(df -h "$MOUNT" 2>/dev/null | tail -1 | awk '{print $2}')
        USED=$(df -h "$MOUNT" 2>/dev/null | tail -1 | awk '{print $3}')
        AVAIL=$(df -h "$MOUNT" 2>/dev/null | tail -1 | awk '{print $4}')
        echo "  $LABEL: $USED used / $SIZE total ($AVAIL available)"
      done
    fi
    ;;
  regenerate)
    generate_config
    ;;
  apply)
    generate_config
    systemctl restart resilio-sync
    echo "Config applied and Resilio Sync restarted"
    ;;
  *)
    echo "Resilio Sync Folder Manager (Per-Folder Volumes)"
    echo ""
    echo "Usage: resilio-folders <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list                     - List configured folders and volumes"
    echo "  status                   - Show volume disk usage"
    echo "  add <key> <folder>       - Add a new folder to Resilio config"
    echo "  remove <folder>          - Remove a folder (keeps data)"
    echo "  regenerate               - Regenerate config from folders.json"
    echo "  apply                    - Regenerate config and restart service"
    echo ""
    echo "Config files:"
    echo "  Folders: $FOLDERS_FILE"
    echo "  Device map: $DEVICE_MAP"
    ;;
esac

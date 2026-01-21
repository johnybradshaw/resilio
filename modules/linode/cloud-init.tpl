#cloud-config
# Storage
bootcmd:
  - sleep 2  # brief delay to let disks settle
  - blkid >> /var/log/cloud-init-blkid.log
  - mkdir -p /tmp /var/log /var/tmp ${base_mount_point}
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - mkdir -p ${config.mount_point}
%{ endfor ~}
  - chmod 1777 /tmp /var/tmp
  - apt-get update
  - apt-get install -y ca-certificates gnupg # Fix for https sources
  - sed -i '/ swap /d' /etc/fstab # Remove swap
  - sed -i '/UUID=.*swap/d' /etc/fstab
  - grub-probe /boot || echo "GRUB can't see /boot!"
  - grub-mkconfig -o /boot/grub/grub.cfg || true
  - update-grub || true
  - sleep 2
# partitioning
disk_setup:
  /dev/sdb:
    table_type: gpt
    layout: [25, 50, 25] # /tmp, /var/log, /var/tmp
    overwrite: true
%{ for name, config in jsondecode(folder_device_map_json) ~}
  ${config.device_path}:
    table_type: gpt
    layout: true
    overwrite: false # Do not overwrite existing data volume
%{ endfor ~}
# formatting
fs_setup:
  # OS disks
  - {device: /dev/sdb1, filesystem: ext4, label: tmpdisk, overwrite: true}
  - {device: /dev/sdb2, filesystem: ext4, label: logdisk, overwrite: true}
  - {device: /dev/sdb3, filesystem: ext4, label: vartmpdisk, overwrite: true}
  # Per-folder data volumes - NEVER overwrite to preserve existing data
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - {device: ${config.partition}, filesystem: ext4, label: ${config.label}, extra_opts: [ "-T", "news" ], overwrite: false}
%{ endfor ~}
# Mount points
mounts:
  # OS mounts
  - [ LABEL=tmpdisk, /tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ LABEL=logdisk, /var/log, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ LABEL=vartmpdisk, /var/tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  # Per-folder application mounts
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - [ LABEL=${config.label}, ${config.mount_point}, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
%{ endfor ~}

# Set the hostname
preserve_hostname: false
fqdn: "${device_name}.${tld}"
hostname: "${device_name}"
prefer_fqdn_over_hostname: true
create_hostname_file: true
manage_etc_hosts: localhost

# SSH Settings
ssh:
  emit_keys_to_console: false
disable_root: true
disable_root_opts: no-port-forwarding,no-agent-forwarding,no-X11-forwarding
ssh_pwauth: false # Disable password authentication
ssh_deletekeys: true
ssh_genkeytypes: [rsa, ecdsa, ed25519]
ssh_publish_hostkeys:
  blacklist: [dsa]
  enabled: true
ssh_quiet_keygen: true
random_seed:
  file: /dev/urandom
  command: ["pollinate", "-r"]
  command_required: true

# Management
ubuntu_pro:
  token: "${ubuntu_advantage_token}"

# Package Management
apt:
  preserve_sources_list: true
  sources:
    resilio_sync:
      source: "deb http://linux-packages.resilio.com/resilio-sync/deb resilio-sync non-free"
      keyid: "E1B42102EBECA969E30D2CA4BE66CC4C3F171DE2"
      keyserver: "keyserver.ubuntu.com"
    eternal_terminal:
      source: "ppa:jgmath2000/et"
snap:
  commands:
    0: [install, canonical-livepatch]
package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  # Security
  - apparmor
  - apparmor-profiles
  - apparmor-utils
  - sshguard
  - aide # Advanced Intrusion Detection Environment
  - auditd # Auditing
  - audispd-plugins # Auditing Plugins
  # System
  - curl
  - gnupg
  - zip
  - unattended-upgrades
  # Utilities
  - ncdu # disk usage
  - rclone # backup to object storage

# User Management
users:
  # Cloud user
  - name: ac-user
    groups: [sudo, users, admin, sshusers]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "${ssh_public_key}"
groups:
  - sshusers

# File Management
write_files:
  # Resilio Sync custom OS settings
  - path: /etc/sysctl.d/99-custom.conf
    content: |
      fs.inotify.max_user_watches   = 524288
      fs.inotify.max_user_instances = 1024
      fs.file-max                   = 2097152
  - path: /etc/systemd/system/resilio-sync.service.d/limits.conf
    content: |
      [Service]
      LimitNOFILE=1048576
  # Unattended Upgrades - APT periodic configuration
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Download-Upgradeable-Packages "1";
      APT::Periodic::Unattended-Upgrade "1";
      APT::Periodic::AutocleanInterval "7";
  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    content: |
      Unattended-Upgrade::Allowed-Origins {
        // Standard Ubuntu origins
        "$${distro_id}:$${distro_codename}";
        "$${distro_id}:$${distro_codename}-security";
        "$${distro_id}:$${distro_codename}-updates";
        "$${distro_id}:$${distro_codename}-proposed";
        "$${distro_id}:$${distro_codename}-backports";
        // Ubuntu Pro ESM origins (requires ubuntu_advantage_token)
        "UbuntuESM:$${distro_codename}-infra-security";
        "UbuntuESM:$${distro_codename}-infra-updates";
        "UbuntuESMApps:$${distro_codename}-apps-security";
        "UbuntuESMApps:$${distro_codename}-apps-updates";
        // Ubuntu CIS benchmarks (usg package)
        "UbuntuCIS:$${distro_codename}";
      };
      Unattended-Upgrade::Package-Blacklist {
      };
      Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
      Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::AutoFixInterruptedDpkg "true";
      Unattended-Upgrade::Automatic-Reboot "true";
      Unattended-Upgrade::Automatic-Reboot-Time "03:00";
      Unattended-Upgrade::SyslogEnable "true";
      Unattended-Upgrade::SyslogFacility "daemon";
  # Logrotate configuration for custom logs
  - path: /etc/logrotate.d/resilio-custom
    permissions: '0644'
    content: |
      # Resilio backup log - rotated daily, keep 7 days
      /var/log/resilio-backup.log {
        su root root
        daily
        rotate 7
        compress
        delaycompress
        missingok
        notifempty
        create 0640 root root
      }

      # Volume expansion log - rotated weekly, keep 4 weeks
      /var/log/volume-expand.log {
        su root root
        weekly
        rotate 4
        compress
        delaycompress
        missingok
        notifempty
        create 0640 root root
      }

      # Cloud-init debug logs - rotated monthly, keep 2 months
      /var/log/cloud-init-blkid.log {
        su root root
        monthly
        rotate 2
        compress
        delaycompress
        missingok
        notifempty
        create 0640 root root
      }
  # SSH access
  - path: /etc/ssh/sshd_config.d/99-cloud-ssh-access.conf
    permissions: '0644'
    owner: root:root
    content: |
      # Only allow members of these groups to SSH in
      AllowGroups sshusers admin

      # Explicitly block root login
      PermitRootLogin no
      # Explicitly block password authentication
      PasswordAuthentication no
      # Disable empty password authentication
      PermitEmptyPasswords no

  # Resilio Sync config
  - path: /etc/resilio-sync/license.key
    permissions: '0644'
    content: "${resilio_license_key}"
  # Default folders config - only used if no config exists on volume
  # Per-folder volumes: each folder mounts at ${base_mount_point}/<folder_name>
  - path: /etc/resilio-sync/default-folders.json
    permissions: '0644'
    content: |
      ${resilio_folders_json}
  # Folder device map - used by scripts to manage volumes
  - path: /etc/resilio-sync/folder-device-map.json
    permissions: '0644'
    content: |
      ${folder_device_map_json}
  # Config template - shared_folders populated from volume at boot
  - path: /etc/resilio-sync/config.json.tpl
    permissions: '0644'
    content: |
      {
        "device_name": "${device_name}.${tld}",
        "listening_port": 8889,
        "storage_path": "${base_mount_point}/.sync",
        "pid_file": "/var/run/resilio-sync/sync.pid",
        "use_upnp": false,
        "shared_folders": FOLDERS_PLACEHOLDER
      }
  # Folder management script - allows non-destructive folder changes via SSH
  # Per-folder volumes: each folder has its own volume and mount point
  - path: /usr/local/bin/resilio-folders
    permissions: '0755'
    content: |
      #!/bin/bash
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

  - path: /etc/audit/rules.d/basic.rules
    permissions: '0644'
    content: |
      -w /etc/passwd -p wa -k identity
      -w /etc/shadow -p wa -k identity
      -w /usr/bin/sudo -p x -k sudo_exec
      -a always,exit -F arch=b64 -S execve -k exec_log
      -w /var/log/audit/ -p wa -k auditlog
      -w /etc/ -p wa -k etc_watch
      -w /etc/crontab -p wa -k cron_changes
      -w /etc/cron.d/ -p wa -k cron_changes
      -w /var/log/wtmp -p wa -k logins
      -w /var/log/lastlog -p wa -k logins
  # Volume auto-expand script - automatically grows filesystem when volumes are resized
  # Per-folder volumes: expands all resilio-* labeled volumes
  - path: /usr/local/bin/volume-auto-expand.sh
    permissions: '0755'
    content: |
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

  # Systemd service for volume auto-expansion
  - path: /etc/systemd/system/volume-auto-expand.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Auto-expand volume filesystem if resized
      DefaultDependencies=no
      Before=resilio-sync.service
      After=local-fs.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/volume-auto-expand.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

  # Resilio backup script - backs up all per-folder volumes
  - path: /usr/local/bin/resilio-backup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      D=$(date +%Y%m%d-%H%M%S)
      H=$(hostname -f)
      L="/var/log/resilio-backup.log"
      DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"
      BUCKET="${object_storage_bucket}"

      log() { echo "[$D] $1" | tee -a "$L"; }

      log "Starting backup of all folders"

      # Check if device map exists
      if [ ! -f "$DEVICE_MAP" ]; then
        log "No device map found, falling back to base mount"
        rclone sync "${base_mount_point}" "r:$BUCKET/$H" \
          --exclude ".sync/StreamsList" --exclude ".sync/DownloadState" --exclude "*.!sync" \
          --transfers 8 --log-file="$L" --log-level INFO
        exit $?
      fi

      # Backup each folder volume separately
      ERRORS=0
      jq -r 'to_entries[] | "\(.key) \(.value.mount_point)"' "$DEVICE_MAP" | \
      while read -r FOLDER_NAME MOUNT_POINT; do
        log "Backing up folder: $FOLDER_NAME from $MOUNT_POINT"
        if rclone sync "$MOUNT_POINT" "r:$BUCKET/$H/$FOLDER_NAME" \
          --exclude ".sync/StreamsList" --exclude ".sync/DownloadState" --exclude "*.!sync" \
          --transfers 8 --log-file="$L" --log-level INFO; then
          log "Backup complete: $FOLDER_NAME"
        else
          log "ERROR: Backup failed for $FOLDER_NAME"
          ERRORS=$((ERRORS + 1))
        fi
      done

      # Cleanup old files
      rclone delete "r:$BUCKET/$H" --min-age 30d >> "$L" 2>&1 || true

      if [ "$ERRORS" -gt 0 ]; then
        log "Backup completed with $ERRORS errors"
        exit 1
      else
        log "Backup completed successfully"
      fi
  - path: /root/.config/rclone/rclone.conf
    permissions: '0600'
    content: |
      [r]
      type=s3
      provider=Ceph
      access_key_id=${object_storage_access_key}
      secret_access_key=${object_storage_secret_key}
      endpoint=${object_storage_endpoint}
      acl=private

  - path: /etc/nftables.conf
    permissions: '0644'
    content: |
      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;
          iifname "lo" accept
          ip saddr 127.0.0.0/8 iifname != "lo" drop
          ip6 saddr ::1 iifname != "lo" drop
          ct state related,established accept
          tcp dport { 22, 2022 } ct state new,established accept
          ip protocol icmp accept
        }
        chain output {
          type filter hook output priority 0; policy drop;
          ct state new,related,established accept
        }
        chain forward {
          type filter hook forward priority 0; policy drop;
        }
      }

# Run Commands
runcmd:
  # Disable and mask UFW in case it's still present
  - [ bash, -c, "echo '--- Disabling UFW (if installed) ---'" ]
  - [ systemctl, disable, ufw ]
  - [ systemctl, mask, ufw ]

  # Enable and apply nftables config
  - [ bash, -c, "echo '--- Enabling and restarting nftables ---'" ]
  - [ systemctl, enable, nftables ]
  - [ systemctl, restart, nftables ]
  - [ bash, -c, "echo '--- nftables ruleset applied ---'" ]

  # Create directories - base mount and per-folder mounts
  - mkdir -p ${base_mount_point}/.sync
  - mkdir -p /var/log/resilio-sync
  - chown rslsync:rslsync /var/log/resilio-sync

  # Activate Ubuntu Advantage
  - pro enable esm-infra esm-apps livepatch usg
  - apt-get update

  # Load custom sysctl settings
  - sysctl --system

  # Install additional packages without prompting
  - |
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      et resilio-sync usg jq cloud-guest-utils \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"

  # Stop services
  - systemctl stop resilio-sync

  # Set ownership on all Resilio Sync mount points
  - chown -R rslsync:rslsync ${base_mount_point} /etc/resilio-sync

  # Initialize folder config from base mount (preserves existing config across instance recreation)
  - |
    BASE_MOUNT="${base_mount_point}"
    FOLDERS_FILE="$BASE_MOUNT/.sync/folders.json"
    DEVICE_MAP="/etc/resilio-sync/folder-device-map.json"

    # Ensure base .sync directory exists
    mkdir -p "$BASE_MOUNT/.sync"

    # Create or use existing folders config
    if [ ! -f "$FOLDERS_FILE" ]; then
      echo ">>> No existing folder config found — creating from defaults"
      cp /etc/resilio-sync/default-folders.json "$FOLDERS_FILE"
      chown rslsync:rslsync "$FOLDERS_FILE"
    else
      echo ">>> Using existing folder config from $FOLDERS_FILE"
    fi

    # Set ownership on each per-folder mount point
    if [ -f "$DEVICE_MAP" ]; then
      jq -r '.[] | .mount_point' "$DEVICE_MAP" | while read -r MOUNT; do
        if [ -d "$MOUNT" ]; then
          chown rslsync:rslsync "$MOUNT"
          echo ">>> Set ownership on $MOUNT"
        fi
      done
    fi

    # Generate config.json from template + volume-based folders
    FOLDERS=$(cat "$FOLDERS_FILE")
    sed "s|FOLDERS_PLACEHOLDER|$FOLDERS|" /etc/resilio-sync/config.json.tpl > /etc/resilio-sync/config.json
    chown rslsync:rslsync /etc/resilio-sync/config.json
    echo ">>> Resilio config generated"

  # Create Resilio Sync identity and apply license
  # Create a new identity only if none exists
  - |
    IDDIR=$(ls -d ${base_mount_point}/.sync/.SyncUser* 2>/dev/null | head -n1)
    if [ -z "$IDDIR" ]; then
      echo ">>> No existing identity found — creating one now"
      sudo -u rslsync /usr/bin/rslsync \
        --config /etc/resilio-sync/config.json \
        --identity "${device_name}.${tld}"
    else
      echo ">>> Identity already present in $IDDIR — skipping identity creation"
    fi

  # Apply the license only if no license folder exists in that identity
  - |
    if ! find ${base_mount_point}/.sync/.SyncUser*/licenses -mindepth 1 -type d | grep -q .; then
      echo ">>> No license found — applying license now"
      sudo -u rslsync /usr/bin/rslsync \
        --config /etc/resilio-sync/config.json \
        --license /etc/resilio-sync/license.key
    else
      echo ">>> License already applied — skipping license step"
    fi

  # Enable volume auto-expansion service (runs on boot before resilio-sync)
  - systemctl daemon-reload
  - systemctl enable volume-auto-expand.service
  - /usr/local/bin/volume-auto-expand.sh  # Run once now in case volume was pre-expanded

  - systemctl enable --now resilio-sync
  # Only enable backup cron if this region is in backup_regions
  - |
    if [ "${enable_backup}" = "true" ] && [ "${object_storage_access_key}" != "CHANGEME" ]; then
      echo "0 2 * * * /usr/local/bin/resilio-backup.sh" | crontab -
      echo ">>> Backup enabled on this region"
    else
      echo ">>> Backup disabled on this region (enable_backup=${enable_backup})"
    fi

  # Load audit rules
  - [ bash, -c, "augenrules --load" ]
  - [ systemctl, enable, auditd ]
  - [ systemctl, restart, auditd ]

  # Restart systemd-logind to apply hostname changes
  - systemctl restart systemd-logind

  # Enable SSHGuard
  - systemctl enable --now sshguard

  # Disable Ctrl-Alt-Del reboot
  - systemctl mask ctrl-alt-del.target
  - systemctl daemon-reload

  # Enable unattended-upgrades, apt-daily timers & AppArmor
  - |
    # Enable apt-daily timers for automatic updates
    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
    systemctl enable --now unattended-upgrades apparmor &&
    aa-enabled &&
    apparmor_parser -a --Complain /etc/apparmor.d/

  # Hardening
    # Initialise AIDE
  - |
    aide --init &&
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  - systemctl enable aidecheck.timer

  # CIS Hardening - DISABLED temporarily due to boot issues
  # Re-enable after validating system boots correctly
  # - |
  #   usg generate-tailoring cis_level1_server hardening.xml &&
  #   usg fix --tailoring-file hardening.xml

# Reboot after Cloud-Init - DISABLED to prevent boot loops
# Re-enable after validating cloud-init completes successfully
# power_state:
#   delay: now
#   mode: reboot
#   message: "Reboot after Cloud-Init completion"
#   condition: True

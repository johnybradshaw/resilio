#cloud-config
# Storage
bootcmd:
  - sleep 2  # brief delay to let disks settle
  - blkid >> /var/log/cloud-init-blkid.log
  - mkdir -p /tmp /var/log /var/tmp ${mount_point}
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
  /dev/sdc:
    table_type: gpt
    layout: true
    overwrite: false # Do not overwrite existing partitions
# formatting
fs_setup:
  # OS disks
  - {device: /dev/sdb1, filesystem: ext4, label: tmpdisk, overwrite: true}
  - {device: /dev/sdb2, filesystem: ext4, label: logdisk, overwrite: true}
  - {device: /dev/sdb3, filesystem: ext4, label: vartmpdisk, overwrite: true}
  # application data - NEVER overwrite to preserve existing data on volume
  - {device: /dev/sdc1, filesystem: ext4, label: resilio, extra_opts: [ "-T", "news" ], overwrite: false}
# Mount points
mounts:
  # OS mounts
  - [ LABEL=tmpdisk, /tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ LABEL=logdisk, /var/log, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ LABEL=vartmpdisk, /var/tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  # Application mounts
  - [ LABEL=resilio, /mnt/resilio-data, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]

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
  - path: /etc/resilio-sync/default-folders.json
    permissions: '0644'
    content: |
      ${resilio_folders_json}
  # Config template - shared_folders populated from volume at boot
  - path: /etc/resilio-sync/config.json.tpl
    permissions: '0644'
    content: |
      {
        "device_name": "${device_name}.${tld}",
        "listening_port": 8889,
        "storage_path": "${mount_point}/.sync",
        "pid_file": "/var/run/resilio-sync/sync.pid",
        "use_upnp": false,
        "shared_folders": FOLDERS_PLACEHOLDER
      }
  # Folder management script - allows non-destructive folder changes via SSH
  - path: /usr/local/bin/resilio-folders
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      MOUNT="${mount_point}"
      FOLDERS_FILE="$MOUNT/.sync/folders.json"
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
          echo "Current folders:"
          cat "$FOLDERS_FILE" | jq -r '.[] | "  - \(.dir) [\(.secret[0:8])...]"'
          ;;
        add)
          if [ -z "$${2:-}" ] || [ -z "$${3:-}" ]; then
            echo "Usage: resilio-folders add <folder_key> <directory_name>"
            echo "Example: resilio-folders add BXXXXXXX... documents"
            exit 1
          fi
          KEY="$2"
          DIR="$3"
          FULL_PATH="$MOUNT/$DIR"
          # Create directory if needed
          mkdir -p "$FULL_PATH"
          chown rslsync:rslsync "$FULL_PATH"
          # Add to folders.json
          jq --arg key "$KEY" --arg dir "$FULL_PATH" \
            '. += [{"secret": $key, "dir": $dir, "use_relay_server": true, "use_tracker": true, "search_lan": false, "use_sync_trash": false, "overwrite_changes": false, "selective_sync": false}]' \
            "$FOLDERS_FILE" > "$FOLDERS_FILE.tmp" && mv "$FOLDERS_FILE.tmp" "$FOLDERS_FILE"
          chown rslsync:rslsync "$FOLDERS_FILE"
          generate_config
          echo "Added folder: $DIR"
          echo "Restart Resilio Sync to apply: sudo systemctl restart resilio-sync"
          ;;
        remove)
          if [ -z "$${2:-}" ]; then
            echo "Usage: resilio-folders remove <directory_name>"
            exit 1
          fi
          DIR="$2"
          FULL_PATH="$MOUNT/$DIR"
          jq --arg dir "$FULL_PATH" 'map(select(.dir != $dir))' \
            "$FOLDERS_FILE" > "$FOLDERS_FILE.tmp" && mv "$FOLDERS_FILE.tmp" "$FOLDERS_FILE"
          chown rslsync:rslsync "$FOLDERS_FILE"
          generate_config
          echo "Removed folder: $DIR (data NOT deleted)"
          echo "Restart Resilio Sync to apply: sudo systemctl restart resilio-sync"
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
          echo "Resilio Sync Folder Manager"
          echo ""
          echo "Usage: resilio-folders <command> [args]"
          echo ""
          echo "Commands:"
          echo "  list                     - List configured folders"
          echo "  add <key> <dir>          - Add a new folder"
          echo "  remove <dir>             - Remove a folder (keeps data)"
          echo "  regenerate               - Regenerate config from folders.json"
          echo "  apply                    - Regenerate config and restart service"
          echo ""
          echo "Folders config: $FOLDERS_FILE"
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
  # Volume auto-expand script - automatically grows filesystem when volume is resized
  - path: /usr/local/bin/volume-auto-expand.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Automatically expand filesystem if volume has been resized
      # Runs on boot via systemd before resilio-sync starts
      set -euo pipefail

      DEVICE="/dev/sdc"
      PARTITION="/dev/sdc1"
      MOUNT="${mount_point}"
      LOG="/var/log/volume-expand.log"

      log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

      # Check if partition exists
      if [ ! -b "$PARTITION" ]; then
        log "Partition $PARTITION not found, skipping expansion"
        exit 0
      fi

      # Get sizes in bytes
      DEVICE_SIZE=$(blockdev --getsize64 "$DEVICE")
      PART_SIZE=$(blockdev --getsize64 "$PARTITION")

      # Calculate difference (account for GPT overhead ~1MB)
      DIFF=$((DEVICE_SIZE - PART_SIZE))
      THRESHOLD=$((100 * 1024 * 1024))  # 100MB threshold

      if [ "$DIFF" -gt "$THRESHOLD" ]; then
        log "Volume resize detected: device=$((DEVICE_SIZE/1024/1024))MB, partition=$((PART_SIZE/1024/1024))MB"
        log "Expanding partition..."

        # Grow partition to fill device
        if growpart "$DEVICE" 1; then
          log "Partition expanded successfully"
        else
          log "ERROR: Failed to expand partition"
          exit 1
        fi

        # Resize filesystem (works online for ext4)
        log "Expanding filesystem..."
        if resize2fs "$PARTITION"; then
          NEW_SIZE=$(blockdev --getsize64 "$PARTITION")
          log "Filesystem expanded successfully: $((NEW_SIZE/1024/1024))MB"
        else
          log "ERROR: Failed to expand filesystem"
          exit 1
        fi
      else
        log "No expansion needed: device and partition sizes match"
      fi

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

  # Resilio backup script
  - path: /usr/local/bin/resilio-backup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      D=$(date +%Y%m%d-%H%M%S)
      H=$(hostname -f)
      L="/var/log/resilio-backup.log"
      echo "[$D] Starting backup" | tee -a "$L"
      rclone sync "${mount_point}" "r:${object_storage_bucket}/$H" \
        --exclude ".sync/StreamsList" --exclude ".sync/DownloadState" --exclude "*.!sync" \
        --transfers 8 --log-file="$L" --log-level INFO && \
      echo "[$D] Backup done" | tee -a "$L" || echo "[$D] Backup failed" | tee -a "$L"
      rclone delete "r:${object_storage_bucket}/$H" --min-age 30d >> "$L" 2>&1 || true
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
  # Disable and mask UFW in case it’s still present
  - [ bash, -c, "echo '--- Disabling UFW (if installed) ---'" ]
  - [ systemctl, disable, ufw ]
  - [ systemctl, mask, ufw ]

  # Enable and apply nftables config
  - [ bash, -c, "echo '--- Enabling and restarting nftables ---'" ]
  - [ systemctl, enable, nftables ]
  - [ systemctl, restart, nftables ]
  - [ bash, -c, "echo '--- nftables ruleset applied ---'" ]

  # Create directories
  - mkdir -p ${mount_point}/.sync
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

  # Set ownership on Resilio Sync files/folders
  - chown -R rslsync:rslsync ${mount_point} /etc/resilio-sync

  # Initialize folder config from volume (preserves existing config across instance recreation)
  - |
    FOLDERS_FILE="${mount_point}/.sync/folders.json"
    if [ ! -f "$FOLDERS_FILE" ]; then
      echo ">>> No existing folder config found — creating from defaults"
      mkdir -p "${mount_point}/.sync"
      cp /etc/resilio-sync/default-folders.json "$FOLDERS_FILE"
      chown rslsync:rslsync "$FOLDERS_FILE"
    else
      echo ">>> Using existing folder config from $FOLDERS_FILE"
    fi
    # Generate config.json from template + volume-based folders
    FOLDERS=$(cat "$FOLDERS_FILE")
    sed "s|FOLDERS_PLACEHOLDER|$FOLDERS|" /etc/resilio-sync/config.json.tpl > /etc/resilio-sync/config.json
    chown rslsync:rslsync /etc/resilio-sync/config.json
    echo ">>> Resilio config generated"

  # Create Resilio Sync identity and apply license
  # Create a new identity only if none exists
  - |
    IDDIR=$(ls -d ${mount_point}/.sync/.SyncUser* 2>/dev/null | head -n1)
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
    if ! find ${mount_point}/.sync/.SyncUser*/licenses -mindepth 1 -type d | grep -q .; then
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
  - |
    if [ "${object_storage_access_key}" != "CHANGEME" ]; then
      echo "0 2 * * * /usr/local/bin/resilio-backup.sh" | crontab -
      echo ">>> Backup enabled"
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

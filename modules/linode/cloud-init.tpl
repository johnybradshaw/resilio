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
  # application data
  - {device: /dev/sdc1, filesystem: ext4, label: resilio, extra_opts: [ "-T", "news" ], overwrite: true}
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
  # Unattended Upgrades
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    content: |
      Unattended-Upgrade::Allowed-Origins {
        "$${distro_id}:$${distro_codename}";
        "$${distro_id}:$${distro_codename}-security";
        "$${distro_id}:$${distro_codename}-updates";
        "$${distro_id}:$${distro_codename}-proposed";
        "$${distro_id}:$${distro_codename}-backports";
      };
      Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
      Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::AutoFixInterruptedDpkg "true";
      Unattended-Upgrade::Automatic-Reboot "true";
      Unattended-Upgrade::Automatic-Reboot-Time "03:00";
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
  - path: /etc/resilio-sync/config.json
    permissions: '0644'
    content: |
      {
        "device_name": "${device_name}.${tld}",
        "listening_port": 8889,
        "storage_path": "${mount_point}/.sync",
        "pid_file": "/var/run/resilio-sync/sync.pid",
        "use_upnp": false,
        "shared_folders": [
          {
            "secret": "${resilio_folder_key}",
            "dir": "${mount_point}/${resilio_folder_key}",
            "use_relay_server": true,
            "use_tracker": true,
            "search_lan": false,
            "use_sync_trash": true,
            "overwrite_changes": false
          }
        ]
      }

  # Set up auditd
  - path: /etc/audit/rules.d/basic.rules
    permissions: '0644'
    content: |
      # Watch for changes to passwd and shadow files
      -w /etc/passwd -p wa -k identity
      -w /etc/shadow -p wa -k identity

      # Monitor sudo usage
      -w /usr/bin/sudo -p x -k sudo_exec

      # Log all command executions (64-bit)
      -a always,exit -F arch=b64 -S execve -k exec_log

      # Monitor changes to audit logs (audit tampering)
      -w /var/log/audit/ -p wa -k auditlog

      # Watch for changes in /etc (configs)
      -w /etc/ -p wa -k etc_watch

      # Monitor crontab changes
      -w /etc/crontab -p wa -k cron_changes
      -w /etc/cron.d/ -p wa -k cron_changes

      # Track logins
      -w /var/log/wtmp -p wa -k logins
      -w /var/log/lastlog -p wa -k logins
  # nftables
  - path: /etc/nftables.conf
    permissions: '0644'
    owner: root:root
    content: |
      # nftables firewall configuration (CIS-style base with custom additions)

      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;

          # Allow loopback traffic
          iifname "lo" accept

          # Drop spoofed loopback traffic not on loopback interface (IPv4 & IPv6)
          ip saddr 127.0.0.0/8 iifname != "lo" drop
          ip6 saddr ::1 iifname != "lo" drop

          # Allow established and related inbound connections
          ct state related,established accept

          # Allow inbound SSH (inc. eternal-terminal)
          tcp dport { 22, 2022 } ct state new,established accept

          # # Allow web traffic (HTTP, HTTPS)
          # tcp dport { 80, 443 } ct state new,established accept

          # # Allow Resilio Sync (default port)
          # tcp dport 55555 ct state new,established accept

          # Allow ping/ICMP
          ip protocol icmp accept
        }

        chain output {
          type filter hook output priority 0; policy drop;

          # Allow all outbound traffic (new, related, established)
          ct state new,related,established accept
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # No forwarding is allowed by default (can be changed if routing is needed)
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

  # Activate Ubuntu Advantage
  - pro enable esm-infra esm-apps livepatch usg
  - apt-get update

  # Load custom sysctl settings
  - sysctl --system

  # Install additional packages without prompting
  - |
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      et resilio-sync usg \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"

  # Stop services
  - systemctl stop resilio-sync

  # Set ownership on Resilio Sync files/folders
  - chown -R rslsync:rslsync ${mount_point} /etc/resilio-sync

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
  - systemctl enable --now resilio-sync

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

  # Enable unattended-upgrades & AppArmor
  - |
    systemctl enable --now unattended-upgrades apparmor &&
    aa-enabled &&
    apparmor_parser -a --Complain /etc/apparmor.d/

  # Hardening
    # Initialise AIDE
  - |
    aide --init &&
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  - systemctl enable aidecheck.timer

  # Add CIS Hardening
  - |
    usg generate-tailoring cis_level1_server hardening.xml &&
    usg fix --tailoring-file hardening.xml

# Reboot after Cloud-Init
power_state:
  delay: now
  mode: reboot
  message: "Reboot after Cloud-Init completion"
  condition: True

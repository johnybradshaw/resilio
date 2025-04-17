#cloud-config
# Storage
bootcmd:
  - mkdir -p /tmp /var/log /var/tmp /mnt/resilio-data
  - chmod 1777 /tmp /var/tmp
  - apt-get update
  - apt-get install -y ca-certificates gnupg # Fix for https sources
# partitioning
disk_setup:
  /dev/sdb:
    table_type: gpt
    layout: [25, 50, 25] # /tmp, /var/log, /var/tmp
    overwrite: true
  /dev/sdc:
    table_type: gpt
    layout: true
    overwrite: false
# formatting
fs_setup:
  # OS disks
  - {device: /dev/sdb1, filesystem: ext4, label: tmpdisk}
  - {device: /dev/sdb2, filesystem: ext4, label: logdisk}
  - {device: /dev/sdb3, filesystem: ext4, label: vartmpdisk}
  # application data
  - {device: /dev/sdc1, filesystem: ext4, label: resilio, extra_opts: [ "-T", "news" ]}
# Mount points
mounts:
  # OS mounts
  - [ /dev/sdb1, /tmp, auto, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ /dev/sdb2, /var/log, auto, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  - [ /dev/sdb3, /var/tmp, auto, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]
  # Application mounts
  - [ /dev/sdc1, /mnt/resilio-data, auto, "defaults,noatime,nosuid,nodev,noexec", "0", "2" ]

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
  - apparmor-profiles-extra
  - apparmor-utils
  - sshguard
  - aide # Advanced Intrusion Detection Environment
  - ufw # Uncomplicated Firewall
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
    groups: [sudo, users, admin]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "${ssh_public_key}"

# File Management
write_files:
  - path: /etc/sysctl.d/99-custom.conf
    content: |
      fs.inotify.max_user_watches   = 524288
      fs.inotify.max_user_instances = 1024
      fs.file-max                   = 2097152

  - path: /etc/systemd/system/resilio-sync.service.d/limits.conf
    content: |
      [Service]
      LimitNOFILE=1048576

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

  - path: /etc/resilio-sync/license.key
    permissions: '0644'
    content: "${resilio_license_key}"

  - path: /etc/resilio-sync/config.json
    permissions: '0644'
    content: |
      {
        "device_name": "${device_name}.${tld}",
        "listening_port": 8889,
        "storage_path": "/mnt/resilio-data/.sync",
        "pid_file": "/var/run/resilio-sync/sync.pid",
        "use_upnp": false,
        "shared_folders": [
          {
            "secret": "${resilio_folder_key}",
            "dir": "/mnt/resilio-data/${resilio_folder_key}",
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

# Run Commands
runcmd:
  # Activate Ubuntu Advantage
  - pro enable esm-infra esm-apps livepatch usg

  # Load custom sysctl settings
  - sysctl --system

  # Install additional packages without prompting
  - |
    DEBIAN_FRONTEND=noninteractive apt-get install -y et resilio-sync \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"

  # Stop services
  - systemctl stop resilio-sync

  # Set ownership on Resilio Sync files/folders
  - chown -R rslsync:rslsync /mnt/resilio-data /etc/resilio-sync

  # Create Resilio Sync identity and apply license
  - sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --identity "${device_name}.${tld}"
  - sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --license /etc/resilio-sync/license.key
  - systemctl enable --now resilio-sync

  # Load audit rules
  - [ bash, -c, "augenrules --load" ]
  - [ systemctl, enable, auditd ]
  - [ systemctl, restart, auditd ]

  # Restart systemd-logind to apply hostname changes
  - systemctl restart systemd-logind

  # Configure UFW firewall rules
  - |
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 2022/tcp
    ufw allow 8889/tcp
    ufw --force enable

  # Enable SSHGuard
  - systemctl enable --now sshguard

  # Disable Ctrl-Alt-Del reboot
  - systemctl mask ctrl-alt-del.target
  - systemctl daemon-reload

  # Enable unattended-upgrades & AppArmor
  - |
    systemctl enable --now unattended-upgrades apparmor &&
    aa-enabled && echo "AppArmor enabled." || echo "AppArmor not enabled." &&
    aa-complain /etc/apparmor.d/*

  # Hardening
    # Add CIS Hardening
  - usg generate-tailoring cis_level1_server hardening.xml
  - usg fix --tailoring-file hardening.xml
    # Initialise AIDE
  - aideinit
  - cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Reboot after Cloud-Init
power_state:
  delay: now
  mode: reboot
  message: "Reboot after Cloud-Init completion"
  condition: True
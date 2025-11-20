#cloud-config
# Minimal, hardened configuration for jumphost
# This jumphost is intentionally minimal - only SSH access to Resilio instances

hostname: ${hostname}
fqdn: ${hostname}

# Package management
package_update: true
package_upgrade: true
package_reboot_if_required: false

packages:
  - fail2ban          # SSH brute force protection
  - ufw               # Firewall (disabled - using Linode firewall)
  - unattended-upgrades # Automatic security updates
  - apt-listchanges   # Track package changes
  - needrestart       # Detect services needing restart
  - sudo              # Sudo access

# SSH hardening
ssh_deletekeys: true
ssh_genkeytypes: [rsa, ecdsa, ed25519]

# Create non-root admin user with sudo access
users:
  - name: ${admin_username}
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}
  - name: root
    lock_passwd: true
    # Root SSH login disabled via sshd_config

# Fail2ban configuration for SSH protection
write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [DEFAULT]
      bantime = 3600
      findtime = 600
      maxretry = 3

      [sshd]
      enabled = true
      port = 22
      logpath = /var/log/auth.log
    permissions: '0644'

  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      # SSH Hardening Configuration
      PermitRootLogin no
      PasswordAuthentication no
      ChallengeResponseAuthentication no
      PubkeyAuthentication yes
      X11Forwarding no
      MaxAuthTries 3
      MaxSessions 2
      ClientAliveInterval 300
      ClientAliveCountMax 2
      AllowAgentForwarding yes
      AllowTcpForwarding yes
      GatewayPorts no
      PermitTunnel no
      Banner /etc/ssh/banner
    permissions: '0644'

  - path: /etc/ssh/banner
    content: |
      ******************************************************************
      * AUTHORIZED ACCESS ONLY                                         *
      * This is a private jumphost for Resilio Sync infrastructure.   *
      * All connections are monitored and logged.                      *
      * Unauthorized access will be prosecuted.                        *
      ******************************************************************
    permissions: '0644'

  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    content: |
      Unattended-Upgrade::Allowed-Origins {
          "$${distro_id}:$${distro_codename}-security";
          "$${distro_id}ESMApps:$${distro_codename}-apps-security";
          "$${distro_id}ESM:$${distro_codename}-infra-security";
      };
      Unattended-Upgrade::AutoFixInterruptedDpkg "true";
      Unattended-Upgrade::MinimalSteps "true";
      Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::Automatic-Reboot "false";
    permissions: '0644'

  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
      APT::Periodic::Download-Upgradeable-Packages "1";
      APT::Periodic::AutocleanInterval "7";
    permissions: '0644'

  - path: /etc/motd
    content: |
      ╔══════════════════════════════════════════════════════════════╗
      ║              JUMPHOST - AUTHORIZED ACCESS ONLY               ║
      ╚══════════════════════════════════════════════════════════════╝

      This jumphost provides secure access to Resilio Sync instances.

      Logged in as: ${admin_username}

      Security Features:
        ✓ SSH key authentication only (no passwords)
        ✓ Root login disabled
        ✓ Fail2ban active (3 failed attempts = 1h ban)
        ✓ Automatic security updates enabled
        ✓ All connections logged
        ✓ Passwordless sudo available

      Usage:
        ssh -J ${admin_username}@THIS_HOST ${admin_username}@resilio-instance

      Sudo usage:
        sudo <command>  # No password required for ${admin_username}

    permissions: '0644'

  - path: /etc/sudoers.d/90-cloud-init-users
    content: |
      # Created by cloud-init - allow ${admin_username} passwordless sudo
      ${admin_username} ALL=(ALL) NOPASSWD:ALL
    permissions: '0440'

# System hardening
bootcmd:
  # Disable IPv6 if not needed
  - echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
  - echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf

runcmd:
  # Apply sysctl settings
  - sysctl -p

  # Enable and start fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban

  # Restart SSH to apply hardening
  - systemctl restart sshd

  # Set timezone
  - timedatectl set-timezone UTC

  # Enable automatic security updates
  - systemctl enable unattended-upgrades
  - systemctl start unattended-upgrades

  # Clear cloud-init artifacts
  - rm -f /var/lib/cloud/instance/boot-finished

# Logging
output:
  all: '| tee -a /var/log/cloud-init-output.log'

# Reboot is not required for jumphost
power_state:
  mode: poweroff
  condition: false

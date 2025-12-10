#cloud-config
# Jumpbox Cloud-Init Configuration
# This is a minimal secure bastion host configuration

# Disable root login immediately
disable_root: true

# Disable password authentication (SSH keys only)
ssh_pwauth: false

# System timezone
timezone: UTC

# Create ac-user with sudo access
users:
  - name: ac-user
    groups: [sudo, users, admin, sshusers]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "${ssh_public_key}"

# Update and upgrade packages
package_update: true
package_upgrade: true

# Install essential packages
packages:
  - vim
  - htop
  - curl
  - wget
  - git
  - fail2ban
  - ufw

# Configure SSH hardening
write_files:
  - path: /etc/ssh/sshd_config.d/99-jumpbox-hardening.conf
    content: |
      # SSH Hardening for Jumpbox
      PermitRootLogin no
      PasswordAuthentication no
      ChallengeResponseAuthentication no
      PubkeyAuthentication yes
      AllowGroups sshusers admin
      MaxAuthTries 3
      MaxSessions 5
      ClientAliveInterval 300
      ClientAliveCountMax 2
    permissions: '0644'

# Run commands after boot
runcmd:
  # Restart SSH to apply hardening
  - systemctl restart sshd

  # Configure fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban

  # Note: UFW is disabled because Linode Cloud Firewall is used
  - systemctl mask ufw
  - systemctl stop ufw || true

  # Set hostname
  - hostnamectl set-hostname jumpbox

final_message: "Jumpbox is ready! SSH as ac-user"

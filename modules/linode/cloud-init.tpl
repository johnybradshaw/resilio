#cloud-config

ssh:
  emit_keys_to_console: false

random_seed:
  file: /dev/urandom
  command: ["pollinate", "-r"]
  command_required: true

chpasswd:
  expire: false
  users:
    - name: root
      type: RANDOM
    - name: ubuntu
      type: RANDOM

manage_etc_hosts: localhost

ubuntu_advantage:
  token: "${ubuntu_advantage_token}"

package_update: true
package_upgrade: true
package_reboot_if_required: true

packages:
  - apparmor
  - apparmor-profiles
  - apparmor-utils
  - apt-transport-https
  - curl
  - gnupg2
  - fail2ban
  - ufw
  - zip
  - unattended-upgrades
  - ncdu # disk usage

snap:
  commands:
    - install canonical-livepatch

users:
  - name: ac-user
    groups: [sudo, users, admin]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "${ssh_public_key}"

write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled    = true
      port       = 22
      filter     = sshd
      logpath    = /var/log/auth.log
      maxretry   = 3
      bantime    = 3600

  - path: /etc/sysctl.d/99-custom.conf
    content: |
      fs.inotify.max_user_watches   = 524288
      fs.inotify.max_user_instances = 1024
      fs.file-max                   = 2097152

  - path: /etc/apt/sources.list.d/resilio-sync.list
    content: |
      deb http://linux-packages.resilio.com/resilio-sync/deb resilio-sync non-free

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

runcmd:
  # set the FQDN
  - hostnamectl set-hostname "${device_name}.${tld}"

  # firewall rules
  - |
    ufw default deny incoming &&
    ufw default allow outgoing &&
    ufw allow 22/tcp && ufw allow 2022/tcp && ufw allow 8889/tcp &&
    ufw --force enable

  # apply Fail2Ban
  - systemctl restart fail2ban

  # install EternalTerminal
  - |
    add-apt-repository -y ppa:jgmath2000/et &&
    apt-get update &&
    apt-get install -y et &&
    systemctl enable --now et

  # disable Ctrl-Alt-Del
  - systemctl mask ctrl-alt-del.target && systemctl daemon-reload

  # tighten SSH
  - |
    sed -i 's/^#\?\s*PermitRootLogin\s\+.*/PermitRootLogin no/' /etc/ssh/sshd_config &&
    sed -i 's/^#\?\s*PasswordAuthentication\s\+.*/PasswordAuthentication no/' /etc/ssh/sshd_config &&
    systemctl restart ssh

  # wait for and mount block device
  - sleep 10
  - |
    set -e
    MNT="/mnt/resilio-data"
    DEV=$(lsblk -dpno NAME,TYPE,MOUNTPOINT | awk '$2=="disk"&&$3==""{print$1;exit}')
    if [ -n "$DEV" ]; then
      blkid "$DEV" || mkfs.ext4 -T news "$DEV"
      mkdir -p "$MNT" && mount "$DEV" "$MNT"
      echo "UUID=$(blkid -s UUID -o value "$DEV") $MNT ext4 defaults,nofail 0 2" >> /etc/fstab
      mount -a
    fi

  # load custom sysctl
  - sysctl --system

  # install & configure Resilio Sync
  - |
    apt-get update &&
    apt-get install -y resilio-sync &&
    systemctl stop resilio-sync &&
    mkdir -p /mnt/resilio-data/.sync &&
    chown -R rslsync:rslsync /mnt/resilio-data &&
    echo "${resilio_license_key}" > /etc/resilio-sync/license.key &&
    cat <<EOF > /etc/resilio-sync/config.json
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
    EOF &&
    chown -R rslsync:rslsync /etc/resilio-sync /var/lib/resilio-sync /mnt/resilio-data &&
    systemctl daemon-reload &&
    sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --identity "${device_name}" &&
    sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --license /etc/resilio-sync/license.key &&
    systemctl enable --now resilio-sync

  # enable unattended-upgrades & AppArmor
  - |
    systemctl enable --now unattended-upgrades apparmor &&
    aa-enabled && echo "AppArmor enabled." || echo "AppArmor not enabled." &&
    aa-complain /etc/apparmor.d/*

power_state:
  delay: "+1"
  mode: reboot
  message: "Reboot after Cloud-Init completion"
  timeout: 30
  condition: True
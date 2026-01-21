#cloud-config
bootcmd:
  - sleep 2
  - blkid >> /var/log/cloud-init-blkid.log
  - mkdir -p /tmp /var/log /var/tmp ${base_mount_point}
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - mkdir -p ${config.mount_point}
%{ endfor ~}
  - chmod 1777 /tmp /var/tmp
  - apt-get update
  - apt-get install -y ca-certificates gnupg
  - sed -i '/ swap /d' /etc/fstab
  - sed -i '/UUID=.*swap/d' /etc/fstab
  - grub-mkconfig -o /boot/grub/grub.cfg || true
  - update-grub || true
disk_setup:
  /dev/sdb:
    table_type: gpt
    layout: [25, 50, 25]
    overwrite: true
%{ for name, config in jsondecode(folder_device_map_json) ~}
  ${config.device_path}:
    table_type: gpt
    layout: true
    overwrite: false
%{ endfor ~}
fs_setup:
  - {device: /dev/sdb1, filesystem: ext4, label: tmpdisk, overwrite: true}
  - {device: /dev/sdb2, filesystem: ext4, label: logdisk, overwrite: true}
  - {device: /dev/sdb3, filesystem: ext4, label: vartmpdisk, overwrite: true}
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - {device: ${config.partition}, filesystem: ext4, label: ${config.label}, extra_opts: ["-T","news"], overwrite: false}
%{ endfor ~}
mounts:
  - [LABEL=tmpdisk, /tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2"]
  - [LABEL=logdisk, /var/log, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2"]
  - [LABEL=vartmpdisk, /var/tmp, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2"]
%{ for name, config in jsondecode(folder_device_map_json) ~}
  - [LABEL=${config.label}, ${config.mount_point}, ext4, "defaults,noatime,nosuid,nodev,noexec", "0", "2"]
%{ endfor ~}
preserve_hostname: false
fqdn: "${device_name}.${tld}"
hostname: "${device_name}"
prefer_fqdn_over_hostname: true
create_hostname_file: true
manage_etc_hosts: localhost
ssh:
  emit_keys_to_console: false
disable_root: true
disable_root_opts: no-port-forwarding,no-agent-forwarding,no-X11-forwarding
ssh_pwauth: false
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
ubuntu_pro:
  token: "${ubuntu_advantage_token}"
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
  - apparmor
  - apparmor-profiles
  - apparmor-utils
  - sshguard
  - aide
  - auditd
  - audispd-plugins
  - curl
  - gnupg
  - zip
  - unattended-upgrades
  - ncdu
  - rclone
users:
  - name: ac-user
    groups: [sudo, users, admin, sshusers]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "${ssh_public_key}"
groups:
  - sshusers
write_files:
  - path: /etc/sysctl.d/99-custom.conf
    content: |
      fs.inotify.max_user_watches=524288
      fs.inotify.max_user_instances=1024
      fs.file-max=2097152
  - path: /etc/systemd/system/resilio-sync.service.d/limits.conf
    content: |
      [Service]
      LimitNOFILE=1048576
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Download-Upgradeable-Packages "1";
      APT::Periodic::Unattended-Upgrade "1";
      APT::Periodic::AutocleanInterval "7";
  - path: /etc/apt/apt.conf.d/50unattended-upgrades
    content: |
      Unattended-Upgrade::Allowed-Origins {
        "$${distro_id}:$${distro_codename}";
        "$${distro_id}:$${distro_codename}-security";
        "$${distro_id}:$${distro_codename}-updates";
        "UbuntuESM:$${distro_codename}-infra-security";
        "UbuntuESM:$${distro_codename}-infra-updates";
        "UbuntuESMApps:$${distro_codename}-apps-security";
        "UbuntuESMApps:$${distro_codename}-apps-updates";
      };
      Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
      Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::AutoFixInterruptedDpkg "true";
      Unattended-Upgrade::Automatic-Reboot "true";
      Unattended-Upgrade::Automatic-Reboot-Time "03:00";
  - path: /etc/logrotate.d/resilio-custom
    permissions: '0644'
    content: |
      /var/log/resilio-backup.log {su root root
        daily
        rotate 7
        compress
        missingok
        notifempty}
      /var/log/volume-expand.log {su root root
        weekly
        rotate 4
        compress
        missingok
        notifempty}
  - path: /etc/ssh/sshd_config.d/99-cloud-ssh-access.conf
    permissions: '0644'
    content: |
      AllowGroups sshusers admin
      PermitRootLogin no
      PasswordAuthentication no
      PermitEmptyPasswords no
  - path: /etc/resilio-sync/license.key
    permissions: '0644'
    content: "${resilio_license_key}"
  - path: /etc/resilio-sync/default-folders.json
    permissions: '0644'
    content: |
      ${resilio_folders_json}
  - path: /etc/resilio-sync/folder-device-map.json
    permissions: '0644'
    content: |
      ${folder_device_map_json}
  - path: /etc/resilio-sync/config.json.tpl
    permissions: '0644'
    content: |
      {"device_name":"${device_name}.${tld}","listening_port":8889,"storage_path":"${base_mount_point}/.sync","pid_file":"/var/run/resilio-sync/sync.pid","use_upnp":false,"shared_folders":FOLDERS_PLACEHOLDER}
  - path: /usr/local/bin/resilio-folders
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      B="${base_mount_point}";F="$B/.sync/folders.json";D="/etc/resilio-sync/folder-device-map.json";T="/etc/resilio-sync/config.json.tpl";C="/etc/resilio-sync/config.json"
      gen(){ [ -f "$F" ]||{ echo "Error: $F not found">&2;exit 1;};sed "s|FOLDERS_PLACEHOLDER|$(cat $F)|" "$T">"$C";chown rslsync:rslsync "$C"; }
      case "$${1:-h}" in
        list) [ -f "$D" ]&&jq -r 'to_entries[]|"  \(.key): \(.value.mount_point)"' "$D";[ -f "$F" ]&&jq -r '.[]|"  \(.dir) [\(.secret[0:8])...]"' "$F";;
        add) [ -z "$${2:-}" ]||[ -z "$${3:-}" ]&&{ echo "Usage: $0 add <key> <name>";exit 1;};P="$B/$3";mkdir -p "$P";chown rslsync:rslsync "$P";jq --arg k "$2" --arg d "$P" '.+=[{"secret":$k,"dir":$d,"use_relay_server":true,"use_tracker":true,"search_lan":false,"use_sync_trash":true,"overwrite_changes":false}]' "$F">"$F.tmp"&&mv "$F.tmp" "$F";chown rslsync:rslsync "$F";gen;;
        remove) [ -z "$${2:-}" ]&&{ echo "Usage: $0 remove <name>";exit 1;};jq --arg d "$B/$2" 'map(select(.dir!=$d))' "$F">"$F.tmp"&&mv "$F.tmp" "$F";chown rslsync:rslsync "$F";gen;;
        status) [ -f "$D" ]&&jq -r 'to_entries[]|.value|"\(.label) \(.mount_point)"' "$D"|while read L M;do echo "$L: $(df -h "$M" 2>/dev/null|tail -1|awk '{print $3"/"$2}')";done;;
        apply) gen;systemctl restart resilio-sync;;
        *) echo "Usage: $0 {list|add|remove|status|apply}";;
      esac
  - path: /etc/audit/rules.d/basic.rules
    permissions: '0644'
    content: |
      -w /etc/passwd -p wa -k identity
      -w /etc/shadow -p wa -k identity
      -w /usr/bin/sudo -p x -k sudo_exec
      -w /var/log/audit/ -p wa -k auditlog
      -w /etc/crontab -p wa -k cron_changes
      -w /var/log/wtmp -p wa -k logins
  - path: /usr/local/bin/volume-auto-expand.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      D="/etc/resilio-sync/folder-device-map.json";B="${base_mount_point}";L="/var/log/volume-expand.log"
      log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"|tee -a "$L"; }
      expand(){
        local DEV="$1" PART="$2" LBL="$3" MNT="$4"
        [ -b "$PART" ]||return 0
        AL=$(blkid -s LABEL -o value "$PART" 2>/dev/null||echo "")
        [ "$AL" = "$LBL" ]||{ log "[$LBL] Label mismatch";return 1; }
        [[ "$MNT" == "$B"/* ]]||return 1
        DS=$(blockdev --getsize64 "$DEV");PS=$(blockdev --getsize64 "$PART")
        [ $((DS-PS)) -gt 104857600 ]&&{ log "[$LBL] Expanding...";growpart "$DEV" 1&&resize2fs "$PART"&&log "[$LBL] Done"; }
      }
      log "Starting expansion check..."
      [ -f "$D" ]||exit 0
      jq -r 'to_entries[]|"\(.value.device_path) \(.value.partition) \(.value.label) \(.value.mount_point)"' "$D"|while read -r DEV PART LBL MNT;do expand "$DEV" "$PART" "$LBL" "$MNT"||true;done
      log "Check complete"
  - path: /etc/systemd/system/volume-auto-expand.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Auto-expand volumes
      Before=resilio-sync.service
      After=local-fs.target
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/volume-auto-expand.sh
      RemainAfterExit=yes
      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/resilio-backup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      D="/etc/resilio-sync/folder-device-map.json";H=$(hostname -f);L="/var/log/resilio-backup.log";K="${object_storage_bucket}"
      log(){ echo "[$(date '+%Y%m%d-%H%M%S')] $1"|tee -a "$L"; }
      log "Starting backup"
      [ -f "$D" ]||{ rclone sync "${base_mount_point}" "r:$K/$H" --exclude ".sync/*" --exclude "*.!sync" --transfers 8 --log-file="$L";exit $?; }
      jq -r 'to_entries[]|"\(.key) \(.value.mount_point)"' "$D"|while read -r N M;do log "Backup $N";rclone sync "$M" "r:$K/$H/$N" --exclude ".sync/*" --exclude "*.!sync" --transfers 8 --log-file="$L"||log "ERROR: $N";done
      rclone delete "r:$K/$H" --min-age 30d >>"$L" 2>&1||true
      log "Backup complete"
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
        chain input {type filter hook input priority 0;policy drop;iifname "lo" accept;ip saddr 127.0.0.0/8 iifname != "lo" drop;ct state related,established accept;tcp dport {22,2022} ct state new,established accept;ip protocol icmp accept;}
        chain output {type filter hook output priority 0;policy drop;ct state new,related,established accept;}
        chain forward {type filter hook forward priority 0;policy drop;}
      }
runcmd:
  - [systemctl, disable, ufw]
  - [systemctl, mask, ufw]
  - [systemctl, enable, nftables]
  - [systemctl, restart, nftables]
  - mkdir -p ${base_mount_point}/.sync /var/log/resilio-sync
  - chown rslsync:rslsync /var/log/resilio-sync
  - pro enable esm-infra esm-apps livepatch usg
  - apt-get update
  - sysctl --system
  - DEBIAN_FRONTEND=noninteractive apt-get install -y et resilio-sync usg jq cloud-guest-utils -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
  - systemctl stop resilio-sync
  - chown -R rslsync:rslsync ${base_mount_point} /etc/resilio-sync
  - |
    B="${base_mount_point}";F="$B/.sync/folders.json";D="/etc/resilio-sync/folder-device-map.json"
    mkdir -p "$B/.sync"
    [ -f "$F" ]||{ cp /etc/resilio-sync/default-folders.json "$F";chown rslsync:rslsync "$F"; }
    [ -f "$D" ]&&jq -r '.[]|.mount_point' "$D"|while read M;do [ -d "$M" ]&&chown rslsync:rslsync "$M";done
    sed "s|FOLDERS_PLACEHOLDER|$(cat $F)|" /etc/resilio-sync/config.json.tpl>/etc/resilio-sync/config.json
    chown rslsync:rslsync /etc/resilio-sync/config.json
  - |
    I=$(ls -d ${base_mount_point}/.sync/.SyncUser* 2>/dev/null|head -n1)
    [ -z "$I" ]&&sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --identity "${device_name}.${tld}"
  - |
    find ${base_mount_point}/.sync/.SyncUser*/licenses -mindepth 1 -type d 2>/dev/null|grep -q .||sudo -u rslsync /usr/bin/rslsync --config /etc/resilio-sync/config.json --license /etc/resilio-sync/license.key
  - systemctl daemon-reload
  - systemctl enable volume-auto-expand.service
  - /usr/local/bin/volume-auto-expand.sh
  - systemctl enable --now resilio-sync
  - |
    [ "${enable_backup}" = "true" ]&&[ "${object_storage_access_key}" != "CHANGEME" ]&&echo "0 2 * * * /usr/local/bin/resilio-backup.sh"|crontab -
  - augenrules --load
  - [systemctl, enable, auditd]
  - [systemctl, restart, auditd]
  - systemctl restart systemd-logind
  - systemctl enable --now sshguard
  - systemctl mask ctrl-alt-del.target
  - systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades apparmor
  - apparmor_parser -a --Complain /etc/apparmor.d/
  - aide --init && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  - systemctl enable aidecheck.timer

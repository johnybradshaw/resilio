# modules/linode/main.tf

locals {
  # Label format: us-east-resilio-sync-a1b2c3d4 (region first, uses global suffix)
  label = "${var.region}-${var.project_name}-${var.suffix}"

  # Hostname for DNS/cloud-init (no suffix, matches DNS record)
  # Format: "us-east.resilio-sync" or just "us-east" depending on include_project_name_in_hostname
  hostname = var.include_project_name_in_hostname ? "${var.region}.${var.project_name}" : var.region

  # Extract non-sensitive folder names for iteration
  # The keys (secrets) are sensitive, but folder names are not
  folder_names = nonsensitive(keys(var.resilio_folders))

  # Sort folder names for consistent device ordering (alphabetically)
  sorted_folder_names = sort(local.folder_names)

  # Map folder names to device letters (starting from sdc) - NON-SENSITIVE for dynamic block
  # sda = boot disk, sdb = tmp disk, sdc+ = data volumes
  # Device letters: c, d, e, f, g, h, i, j, k, l, m, n, o (13 max)
  # IMPORTANT: ext4 filesystem labels are limited to 16 characters!
  # Format: rs-{name} truncated to 16 chars (region not needed - unique per instance)
  folder_device_map_nonsensitive = {
    for idx, name in local.sorted_folder_names : name => {
      device_name = "sd${substr("cdefghijklmnop", idx, 1)}"
      device_path = "/dev/sd${substr("cdefghijklmnop", idx, 1)}"
      partition   = "/dev/sd${substr("cdefghijklmnop", idx, 1)}1"
      label       = substr("rs-${name}", 0, 16)
      mount_point = "/mnt/resilio-data/${name}"
      volume_id   = var.folder_volumes[name].id
    }
  }

  # Full device map including sensitive key - used only for cloud-init JSON
  folder_device_map = {
    for idx, name in local.sorted_folder_names : name => {
      device_name = "sd${substr("cdefghijklmnop", idx, 1)}"
      device_path = "/dev/sd${substr("cdefghijklmnop", idx, 1)}"
      partition   = "/dev/sd${substr("cdefghijklmnop", idx, 1)}1"
      label       = substr("rs-${name}", 0, 16)
      mount_point = "/mnt/resilio-data/${name}"
      volume_id   = var.folder_volumes[name].id
      key         = var.resilio_folders[name].key
      size        = nonsensitive(var.resilio_folders[name].size)
    }
  }

  # Generate Resilio folders JSON for cloud-init (for config.json)
  resilio_folders_config = [
    for name in local.sorted_folder_names : {
      secret            = var.resilio_folders[name].key
      dir               = "/mnt/resilio-data/${name}"
      use_relay_server  = true
      use_tracker       = true
      search_lan        = false
      use_sync_trash    = true
      overwrite_changes = false
    }
  ]
}

resource "linode_instance" "resilio" {
  label  = local.label
  region = var.region
  type   = var.instance_type
  tags = concat(
    var.tags, [
      "region: ${var.region}",
      "service: lin"
    ]
  )
  backups_enabled      = true
  interface_generation = "legacy_config"
  firewall_id          = var.firewall_id

  # Apply user data (cloud-init)
  # Using base64gzip to compress cloud-init template (26KB -> ~6KB)
  # This is required because Linode user_data limit is 16KB decoded
  metadata {
    user_data = base64gzip(templatefile("${path.module}/cloud-init.tpl", {
      device_name            = local.hostname # Clean hostname for FQDN (e.g., us-east.resilio-sync)
      instance_label         = local.label    # Full label with suffix for identification
      ssh_public_key         = var.ssh_public_key
      folder_device_map_json = jsonencode(local.folder_device_map_nonsensitive)
      resilio_folders_json   = jsonencode(local.resilio_folders_config)
      resilio_license_key    = var.resilio_license_key
      tld                    = var.tld
      ubuntu_advantage_token = var.ubuntu_advantage_token
      base_mount_point       = "/mnt/resilio-data"
      # Legacy backup variables (for backward compatibility)
      object_storage_access_key = var.object_storage_access_key
      object_storage_secret_key = var.object_storage_secret_key
      object_storage_endpoint   = var.object_storage_endpoint
      object_storage_bucket     = var.object_storage_bucket
      enable_backup             = var.enable_backup
      # New backup configuration
      backup_config_json = jsonencode({
        enabled          = var.backup_config.enabled
        mode             = var.backup_config.mode
        schedule         = var.backup_config.schedule
        transfers        = var.backup_config.transfers
        bandwidth_limit  = var.backup_config.bandwidth_limit
        versioning       = var.backup_config.versioning
        retention_days   = var.backup_config.retention_days
        primary_endpoint = var.backup_config.primary_endpoint
        primary_bucket   = var.backup_config.primary_bucket
        all_buckets      = var.backup_config.all_buckets
      })
      backup_access_key = var.backup_config.access_key
      backup_secret_key = var.backup_config.secret_key
      # SSL certificate for HTTPS
      ssl_certificate = var.ssl_certificate
      ssl_private_key = var.ssl_private_key
      ssl_issuer_cert = var.ssl_issuer_cert
      # User and webUI passwords
      user_password  = random_password.passwords["user_password"].result
      webui_password = random_password.passwords["webui_password"].result
    }))
  }

  lifecycle {
    ignore_changes        = [metadata]
    create_before_destroy = true
  }
}

resource "linode_instance_disk" "resilio_boot_disk" {
  linode_id = linode_instance.resilio.id

  label           = "boot"
  size            = 20000 # 20GB for OS + security packages
  image           = "linode/ubuntu24.04"
  filesystem      = "ext4"
  root_pass       = random_password.root_password.result
  authorized_keys = [var.ssh_public_key]

  lifecycle {
    prevent_destroy = false
  }
}

resource "linode_instance_disk" "resilio_tmp_disk" {
  label      = "tmp"
  linode_id  = linode_instance.resilio.id
  filesystem = "raw"
  size       = 4000
}

resource "linode_instance_config" "resilio" {
  label     = "resilio_boot_config"
  linode_id = linode_instance.resilio.id

  # Boot disk (sda)
  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.resilio_boot_disk.id
  }

  # Temp disk (sdb) - for /tmp, /var/log, /var/tmp
  device {
    device_name = "sdb"
    disk_id     = linode_instance_disk.resilio_tmp_disk.id
  }

  # Dynamic volume devices (sdc, sdd, sde, etc.) - one per folder
  dynamic "device" {
    for_each = local.folder_device_map_nonsensitive
    content {
      device_name = device.value.device_name
      volume_id   = device.value.volume_id
    }
  }

  root_device = "/dev/sda"
  kernel      = "linode/grub2"
  booted      = true

  lifecycle {
    ignore_changes = [booted]
  }
}

resource "random_password" "root_password" {
  length  = 32
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

resource "random_password" "passwords" {
  for_each         = toset(["user_password", "webui_password"])
  length           = 32
  special          = true
  override_special = "!@#$%^&*()_+-=[]{}|;:,.<>?"

  lifecycle {
    ignore_changes = [length, special, override_special]
  }
}

# Script provisioner - transfers scripts via SSH after instance boot
# This keeps cloud-init under 16KB by moving large scripts out of user_data
resource "null_resource" "provision_scripts" {
  count = var.provision_scripts ? 1 : 0

  depends_on = [linode_instance_config.resilio]

  triggers = {
    instance_id = linode_instance.resilio.id
  }

  connection {
    type        = "ssh"
    user        = "ac-user"
    private_key = var.ssh_private_key
    host        = tolist(linode_instance.resilio.ipv4)[0]

    bastion_host        = var.jumpbox_ip
    bastion_user        = "ac-user"
    bastion_private_key = var.ssh_private_key
  }

  # Transfer resilio-folders script
  provisioner "file" {
    content = templatefile("${path.module}/../../scripts/cloud-init/resilio-folders.sh.tpl", {
      base_mount_point = "/mnt/resilio-data"
    })
    destination = "/tmp/resilio-folders"
  }

  # Transfer volume-auto-expand script
  provisioner "file" {
    content = templatefile("${path.module}/../../scripts/cloud-init/volume-auto-expand.sh.tpl", {
      base_mount_point = "/mnt/resilio-data"
    })
    destination = "/tmp/volume-auto-expand.sh"
  }

  # Transfer resilio-backup script
  provisioner "file" {
    content = templatefile("${path.module}/../../scripts/cloud-init/resilio-backup.sh.tpl", {
      base_mount_point      = "/mnt/resilio-data"
      object_storage_bucket = var.object_storage_bucket
    })
    destination = "/tmp/resilio-backup.sh"
  }

  # Transfer resilio-rehydrate script
  provisioner "file" {
    content = templatefile("${path.module}/../../scripts/cloud-init/resilio-rehydrate.sh.tpl", {
      base_mount_point      = "/mnt/resilio-data"
      object_storage_bucket = var.object_storage_bucket
    })
    destination = "/tmp/resilio-rehydrate.sh"
  }

  # Transfer resilio-backup-watch script
  provisioner "file" {
    content = templatefile("${path.module}/../../scripts/cloud-init/resilio-backup-watch.sh.tpl", {
      base_mount_point = "/mnt/resilio-data"
    })
    destination = "/tmp/resilio-backup-watch.sh"
  }

  # Transfer collect-diagnostics script (no template variables)
  provisioner "file" {
    source      = "${path.module}/../../scripts/cloud-init/collect-diagnostics.sh"
    destination = "/tmp/collect-diagnostics.sh"
  }

  # Install scripts and set permissions
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/resilio-folders /usr/local/bin/resilio-folders",
      "sudo mv /tmp/volume-auto-expand.sh /usr/local/bin/volume-auto-expand.sh",
      "sudo mv /tmp/resilio-backup.sh /usr/local/bin/resilio-backup.sh",
      "sudo mv /tmp/resilio-rehydrate.sh /usr/local/bin/resilio-rehydrate.sh",
      "sudo mv /tmp/resilio-backup-watch.sh /usr/local/bin/resilio-backup-watch.sh",
      "sudo mv /tmp/collect-diagnostics.sh /usr/local/bin/collect-diagnostics.sh",
      "sudo chmod +x /usr/local/bin/resilio-folders",
      "sudo chmod +x /usr/local/bin/volume-auto-expand.sh",
      "sudo chmod +x /usr/local/bin/resilio-backup.sh",
      "sudo chmod +x /usr/local/bin/resilio-rehydrate.sh",
      "sudo chmod +x /usr/local/bin/resilio-backup-watch.sh",
      "sudo chmod +x /usr/local/bin/collect-diagnostics.sh",
      "echo 'Scripts installed successfully'"
    ]
  }
}

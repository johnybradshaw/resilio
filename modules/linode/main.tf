# modules/linode/main.tf

# Generate a unique identifier for this instance
resource "random_id" "instance" {
  byte_length = 4

  keepers = {
    # Regenerate if project name or region changes
    project_name = var.project_name
    region       = var.region
  }
}

locals {
  # Label format: resilio-sync-us-east-a1b2c3d4
  label = "${var.project_name}-${var.region}-${random_id.instance.hex}"

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
      device_name            = local.label
      ssh_public_key         = var.ssh_public_key
      folder_device_map_json = jsonencode(local.folder_device_map_nonsensitive)
      resilio_folders_json   = jsonencode(local.resilio_folders_config)
      resilio_license_key    = var.resilio_license_key
      tld                    = var.tld
      ubuntu_advantage_token = var.ubuntu_advantage_token
      base_mount_point       = "/mnt/resilio-data"
      object_storage_access_key = var.object_storage_access_key
      object_storage_secret_key = var.object_storage_secret_key
      object_storage_endpoint   = var.object_storage_endpoint
      object_storage_bucket     = var.object_storage_bucket
      enable_backup             = var.enable_backup
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
  size            = 8000
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

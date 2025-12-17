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
  # Uses hyphens (required) and adds unique suffix to avoid conflicts
  label = "${var.project_name}-${var.region}-${random_id.instance.hex}"

  # Support both old single key and new multiple keys for backward compatibility
  folder_keys = var.resilio_folder_key != "" ? concat([var.resilio_folder_key], var.resilio_folder_keys) : var.resilio_folder_keys

  # Validate that at least one folder key is provided
  _validate_folder_keys = length(local.folder_keys) > 0 ? true : tobool("ERROR: At least one Resilio folder key must be provided via resilio_folder_keys or resilio_folder_key")

  # Generate JSON configuration for shared folders
  resilio_folders = [
    for key in local.folder_keys : {
      secret            = key
      dir               = "/mnt/resilio-data/${key}"
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
      "region: ${var.region}", # e.g. "region: us-east"
      "service: lin"           # e.g. "service: linode"
    ]
  )
  backups_enabled      = true            # Disable backups ([optional] and not available to managed customers)
  interface_generation = "legacy_config" # Force legacy networking; new interfaces API returns 404 on some accounts
  firewall_id          = var.firewall_id # Attach firewall during instance creation
  # Don't set booted - let it default, config will control boot

  # Apply user data (cloud-init)
  metadata { # Requires base64encoding or errors
    user_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
      device_name                = local.label
      ssh_public_key             = var.ssh_public_key
      volume_id                  = var.volume_id
      resilio_folders_json       = jsonencode(local.resilio_folders)
      resilio_license_key        = var.resilio_license_key
      tld                        = var.tld
      ubuntu_advantage_token     = var.ubuntu_advantage_token
      mount_point                = "/mnt/resilio-data"
      object_storage_access_key  = var.object_storage_access_key
      object_storage_secret_key  = var.object_storage_secret_key
      object_storage_endpoint    = var.object_storage_endpoint
      object_storage_bucket      = var.object_storage_bucket
      })
    )
  }
}

resource "linode_instance_disk" "resilio_boot_disk" {
  linode_id = linode_instance.resilio.id

  label           = "boot"
  size            = 8000                 # 8GB
  image           = "linode/ubuntu24.04" # Initial image
  filesystem      = "ext4"
  root_pass       = random_password.root_password.result
  authorized_keys = [var.ssh_public_key]

  lifecycle {
    # Prevent accidental deletion of boot disk
    prevent_destroy = false # Set to true in production if needed
  }
}

resource "linode_instance_disk" "resilio_tmp_disk" {
  label      = "tmp"
  linode_id  = linode_instance.resilio.id
  filesystem = "raw" # To support cloud-init partitioning

  size = 4000 # 4GB

}

resource "linode_instance_config" "resilio" {
  label     = "resilio_boot_config"
  linode_id = linode_instance.resilio.id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.resilio_boot_disk.id
  }
  device {
    device_name = "sdb" # /tmp / var/log /var/tmp
    disk_id     = linode_instance_disk.resilio_tmp_disk.id
  }
  device {
    device_name = "sdc" # /mnt/resilio-data
    volume_id   = var.volume_id
  }

  # Use legacy interface block to provision the default public NIC before boot
  # interfaces {
  #   purpose = "public"
  #   primary = true
  # }

  root_device = "/dev/sda"
  kernel      = "linode/grub2" # To support AppArmor etc
  booted      = true
  lifecycle {
    # Ignore changes to booted after initial creation
    ignore_changes = [booted]
  }
}

resource "random_password" "root_password" {
  length  = 32
  special = true

  lifecycle {
    # Keep the same password across terraform runs
    ignore_changes = [length, special]
  }
}

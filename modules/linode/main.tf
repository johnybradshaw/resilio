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
}

resource "linode_instance" "resilio" {
  label            = local.label
  region           = var.region
  type             = var.instance_type
  tags             = concat(
    var.tags, [
      "region: ${var.region}", # e.g. "region: us-east"
      "service: lin" # e.g. "service: linode"
    ]
  )
  backups_enabled = true # Disable backups ([optional] and not available to managed customers)
  interface_generation = "linode" # Use new interface system in provider 3.x
  # Don't set booted - let it default, config will control boot

  # Apply user data (cloud-init)
  metadata { # Requires base64encoding or errors
    user_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
      device_name       = local.label
      ssh_public_key    = var.ssh_public_key
      volume_id         = var.volume_id
      resilio_folder_key = var.resilio_folder_key
      resilio_license_key = var.resilio_license_key
      tld = var.tld
      ubuntu_advantage_token = var.ubuntu_advantage_token
      mount_point = "/mnt/resilio-data"
    })
    )
  }
}

resource "linode_instance_disk" "resilio_boot_disk" {
  linode_id = linode_instance.resilio.id

  label     = "boot"
  size  = 8000 # 8GB
  image = "linode/ubuntu24.04" # Initial image
  filesystem = "ext4"
  root_pass         = random_password.root_password.result
  authorized_keys   = [var.ssh_public_key]

  lifecycle {
    # Prevent accidental deletion of boot disk
    prevent_destroy = false  # Set to true in production if needed
  }
}

resource "linode_instance_disk" "resilio_tmp_disk" {
  label     = "tmp"
  linode_id = linode_instance.resilio.id
  filesystem = "raw" # To support cloud-init partitioning

  size  = 4000 # 4GB
  
}

resource "linode_instance_config" "resilio" {
  # Depends on interface being created first
  depends_on = [linode_interface.public]

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

  # NO interface block - using standalone linode_interface resource instead

  root_device = "/dev/sda"
  kernel      = "linode/grub2" # To support AppArmor etc
  booted      = true
  lifecycle {
    # Ignore changes to booted after initial creation
    ignore_changes = [booted]
  }
}

# Public network interface - new in provider 3.x
resource "linode_interface" "public" {
  # Must wait for disks to be created before adding interface
  depends_on = [
    linode_instance_disk.resilio_boot_disk,
    linode_instance_disk.resilio_tmp_disk
  ]

  linode_id = linode_instance.resilio.id

  public = {
    ipv4 = {
      addresses = [
        {
          address = "auto"
          primary = true
        }
      ]
    }
    ipv6 = {
      ranges = [
        {
          range = "/64"
        }
      ]
    }
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
# modules/linode/main.tf
locals {   label = "${var.project_name}.${var.region}" } # e.g. "resilio-sync.us-east"
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
  
  # Apply user data (cloud-init)
  metadata { # Rquires base64encoding or errors
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
  
  # lifecycle {
  #   ignore_changes = [ metadata ] # Ignore changes to user_data as it will be recreated
  # }
  # boot_config_label = "Default Configuration"
}

resource "linode_instance_disk" "resilio_boot_disk" {
  linode_id = linode_instance.resilio.id

  label     = "boot"
  size  = 8000 # 8GB
  image = "linode/ubuntu24.04" # Initial image
  filesystem = "ext4"
  root_pass         = random_password.root_password.result
  authorized_keys   = [var.ssh_public_key]
}

resource "linode_instance_disk" "resilio_tmp_disk" {
  label     = "tmp"
  linode_id = linode_instance.resilio.id
  filesystem = "raw" # To support cloud-init partitioning

  size  = 4000 # 4GB
  
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

  root_device = "/dev/sda"
  kernel      = "linode/grub2" # To support AppArmor etc
  booted      = true
  lifecycle { 
    # Ignore changes to booted after initial creation
    ignore_changes = [booted]
  }
}

resource "random_password" "root_password" {
  length = 32
  special = true
}
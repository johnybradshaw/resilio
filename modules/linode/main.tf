# modules/linode/main.tf
data "linode_profile" "me" {}
resource "linode_instance" "resilio" {
  label            = "${var.project_name}-${var.region}"
  region           = var.region
  type             = var.instance_type
  # image            = "linode/ubuntu24.04"
  # authorized_keys  = [var.ssh_public_key]
  # swap_size        = 256
  
  # group            = var.project_name
  tags             = ["terraform", "resilio-sync", var.region]
  
  # Correct metadata structure with user_data inside
  metadata { # Rquires base64encoding or errors
    user_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
      device_name       = "${var.project_name}-${var.region}"
      ssh_public_key    = var.ssh_public_key
      volume_id         = var.volume_id
      resilio_folder_key = var.resilio_folder_key
      resilio_license_key = var.resilio_license_key
      ubuntu_advantage_token = var.ubuntu_advantage_token
      tld = var.tld
    })
    )
  }
  
  # boot_config_label = "Default Configuration"
}

resource "linode_instance_disk" "resilio_boot_disk" {
  label     = "boot"
  linode_id = linode_instance.resilio.id

  size  = 8000
  image = "linode/ubuntu24.04"

  # Any of authorized_keys, authorized_users, and root_pass
  # can be used for provisioning.
  root_pass         = random_password.root_password.result
  authorized_users  = [data.linode_profile.me.username]
  authorized_keys   = [var.ssh_public_key]
}

resource "linode_instance_config" "resilio" {
  label     = "resilio_boot_config"
  linode_id = linode_instance.resilio.id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.resilio_boot_disk.id
  }

  device {
    device_name = "sdb"
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
# modules/jumphost/main.tf
# Minimal, hardened jumphost for secure SSH access to Resilio instances

resource "linode_instance" "jumphost" {
  label  = "${var.project_name}-jumphost"
  region = var.region
  type   = "g6-nanode-1" # Smallest instance (1GB RAM, 1 CPU, 25GB SSD)
  tags = concat(
    var.tags, [
      "region: ${var.region}",
      "service: jumphost"
    ]
  )

  # Enable backups for recovery
  backups_enabled = true

  # Minimal cloud-init for hardening
  metadata {
    user_data = base64encode(templatefile("${path.module}/jumphost-init.tpl", {
      ssh_public_key = var.ssh_public_key
      hostname       = "${var.project_name}-jumphost"
      admin_username = var.admin_username
    }))
  }
}

resource "linode_instance_disk" "jumphost_boot" {
  linode_id = linode_instance.jumphost.id

  label      = "boot"
  size       = 24576 # 24GB (leave room for swap)
  image      = "linode/ubuntu24.04"
  filesystem = "ext4"
  root_pass  = random_password.jumphost_password.result
  authorized_keys = [var.ssh_public_key]

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

resource "linode_instance_disk" "jumphost_swap" {
  linode_id = linode_instance.jumphost.id

  label      = "swap"
  size       = 512 # 512MB swap
  filesystem = "swap"
}

resource "linode_instance_config" "jumphost" {
  label     = "jumphost_config"
  linode_id = linode_instance.jumphost.id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.jumphost_boot.id
  }
  device {
    device_name = "sdb"
    disk_id     = linode_instance_disk.jumphost_swap.id
  }

  root_device = "/dev/sda"
  kernel      = "linode/grub2"
  booted      = true

  # Networking helpers
  helpers {
    updatedb_disabled = true
  }

  lifecycle {
    ignore_changes = [booted]
  }
}

resource "random_password" "jumphost_password" {
  length  = 32
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Dedicated firewall for jumphost
resource "linode_firewall" "jumphost" {
  label           = "${var.project_name}-jumphost-firewall"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  # Allow SSH only from specified CIDR (your IP)
  inbound {
    label    = "allow-ssh-from-admin"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = [var.allowed_ssh_cidr]
  }

  # Allow ping from admin
  inbound {
    label    = "allow-ping-from-admin"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = [var.allowed_ssh_cidr]
  }

  linodes = [linode_instance.jumphost.id]

  tags = concat(var.tags, ["service: jumphost"])
}

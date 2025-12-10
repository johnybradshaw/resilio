# modules/jumpbox/main.tf
# Random password for root account (required by Linode API)
resource "random_password" "root" {
  length  = 32
  special = true
}

# Jumpbox Linode instance
resource "linode_instance" "jumpbox" {
  label     = "${var.project_name}-jumpbox"
  region    = var.region
  type      = var.instance_type
  image     = "linode/ubuntu24.04"
  root_pass = random_password.root.result
  tags = concat(
    var.tags, [
      "region: ${var.region}",
      "service: jumpbox"
    ]
  )

  # Attach to firewall
  firewall_id = var.firewall_id

  # Enable backups
  backups_enabled      = true
  interface_generation = "legacy_config" # Force legacy networking; new interfaces API returns 404 on some accounts
  # Configure the instance with cloud-init
  metadata {
    user_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
      ssh_public_key = var.ssh_public_key
    }))
  }
}

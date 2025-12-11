# modules/jumpbox-firewall/main.tf

# Generate a unique identifier for this firewall
resource "random_id" "jumpbox_firewall" {
  byte_length = 4

  keepers = {
    # Regenerate if project name changes
    project_name = var.project_name
  }
}

# Create a Linode firewall for the jumpbox
resource "linode_firewall" "jumpbox" {
  label           = "${var.project_name}-jumpbox-firewall-${random_id.jumpbox_firewall.hex}"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  # Allow SSH from external network to jumpbox
  inbound {
    label    = "external-to-jumpbox-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,2022"
    ipv4     = [var.allowed_ssh_cidr]
  }

  # Allow ICMP ping from external network to jumpbox
  inbound {
    label    = "external-to-jumpbox-ping"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = [var.allowed_ssh_cidr]
  }

  tags = var.tags
}

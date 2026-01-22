# modules/jumpbox-firewall/main.tf

# Create a Linode firewall for the jumpbox (uses global suffix for consistency)
resource "linode_firewall" "jumpbox" {
  label           = "${var.project_name}-jumpbox-fw-${var.suffix}"
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

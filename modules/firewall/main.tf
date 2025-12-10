# modules/firewall/main.tf

# Generate a unique identifier for this firewall
resource "random_id" "firewall" {
  byte_length = 4

  keepers = {
    # Regenerate if project name changes
    project_name = var.project_name
  }
}

# Create a Linode firewall
resource "linode_firewall" "resilio" {
  label = "${var.project_name}-firewall-${random_id.firewall.hex}"
  inbound_policy = "DROP"
  outbound_policy = "ACCEPT"

  # Allow SSH from external network to jumpbox
  inbound {
    label    = "external-to-jumpbox-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,2022"
    ipv4     = [ var.allowed_ssh_cidr ]
  }
  inbound {
    label    = "external-to-jumpbox-ping"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = [ var.allowed_ssh_cidr ]
  }

  # Allow SSH from jumpbox to resilio instances (if jumpbox IP is provided)
  dynamic "inbound" {
    for_each = var.jumpbox_ipv4 != null ? [1] : []
    content {
      label    = "jumpbox-to-resilio-ssh"
      action   = "ACCEPT"
      protocol = "TCP"
      ports    = "22,2022"
      ipv4     = [ "${var.jumpbox_ipv4}/32" ]
      ipv6     = var.jumpbox_ipv6 != null ? [ var.jumpbox_ipv6 ] : []
    }
  }

  # Allow all traffic between Linodes on the public network (if IPs are provided)
  dynamic "inbound" {
    for_each = length(var.linode_ipv4) > 0 ? [1] : []
    content {
      label    = "resilio-all-tcp"
      action   = "ACCEPT"
      protocol = "TCP"
      ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
      ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
    }
  }
  dynamic "inbound" {
    for_each = length(var.linode_ipv4) > 0 ? [1] : []
    content {
      label    = "resilio-all-udp"
      action   = "ACCEPT"
      protocol = "UDP"
      ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
      ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
    }
  }
  dynamic "inbound" {
    for_each = length(var.linode_ipv4) > 0 ? [1] : []
    content {
      label    = "resilio-all-icmp"
      action   = "ACCEPT"
      protocol = "ICMP"
      ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
      ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
    }
  }

  # Don't attach linodes here - let them attach during creation via firewall_id
  # linodes = []

  tags = var.tags
}
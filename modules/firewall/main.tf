# modules/firewall/main.tf
# Create a Linode firewall
resource "linode_firewall" "resilio" {
  label = "${var.project_name}-firewall"
  inbound_policy = "DROP"
  outbound_policy = "ACCEPT"

  # Allow all traffic between Linodes on the public network
  inbound {
    label    = "resilio-all-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
    ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
  }
  inbound {
    label    = "resilio-all-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
    ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
  }
  inbound {
    label    = "resilio-all-icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
    ipv6 = var.linode_ipv6  # Linode returns IPv6 addresses with /128 CIDR notation
  }

  # Allow SSH from jumphost (if enabled) or from allowed_ssh_cidr (legacy/fallback)
  dynamic "inbound" {
    for_each = length(var.jumphost_ipv4) > 0 || var.allowed_ssh_cidr != "" ? [1] : []
    content {
      label    = length(var.jumphost_ipv4) > 0 ? "jumphost-ssh-only" : "direct-ssh-access"
      action   = "ACCEPT"
      protocol = "TCP"
      ports    = "22,2022"
      ipv4     = length(var.jumphost_ipv4) > 0 ? [for ip in var.jumphost_ipv4 : "${ip}/32"] : [var.allowed_ssh_cidr]
    }
  }

  # Allow ICMP from jumphost (if enabled) or from allowed_ssh_cidr (legacy/fallback)
  dynamic "inbound" {
    for_each = length(var.jumphost_ipv4) > 0 || var.allowed_ssh_cidr != "" ? [1] : []
    content {
      label    = length(var.jumphost_ipv4) > 0 ? "jumphost-ping-only" : "direct-ping-access"
      action   = "ACCEPT"
      protocol = "ICMP"
      ipv4     = length(var.jumphost_ipv4) > 0 ? [for ip in var.jumphost_ipv4 : "${ip}/32"] : [var.allowed_ssh_cidr]
    }
  }

  linodes = var.linode_id

}
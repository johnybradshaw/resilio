# modules/firewall/main.tf
# Fetch our caller IP from a public “what’s-my-ip” endpoint
data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"    # returns e.g. “1.2.3.4\n”
}

locals {
  my_ip_cidr = format("%s/32", chomp(data.http.my_ip.response_body))
}

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
    ipv6 = [ for ip in var.linode_ipv6 : "${ip}" ] # Already contains "::/128"
  }
    inbound {
    label    = "resilio-all-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
    ipv6 = [ for ip in var.linode_ipv6 : "${ip}" ] # Already contains "::/128"
  }
    inbound {
    label    = "resilio-all-icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4 = [ for ip in var.linode_ipv4 : "${ip}/32" ]
    ipv6 = [ for ip in var.linode_ipv6 : "${ip}" ] # Already contains "::/128"
  }

  # Allow SSH from the jump host only
  inbound {
    label    = "jump-host-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,2022"
    ipv4     = [ local.my_ip_cidr ]
  }
  inbound {
    label    = "jump-host-ping"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = [ local.my_ip_cidr ]
  }

  linodes = var.linode_id

}
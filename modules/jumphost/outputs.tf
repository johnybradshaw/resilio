# modules/jumphost/outputs.tf

output "jumphost_id" {
  description = "ID of the jumphost instance"
  value       = linode_instance.jumphost.id
}

output "jumphost_ipv4" {
  description = "IPv4 address of the jumphost"
  value       = linode_instance.jumphost.ipv4
}

output "jumphost_ipv6" {
  description = "IPv6 address of the jumphost"
  value       = linode_instance.jumphost.ipv6
}

output "jumphost_label" {
  description = "Label of the jumphost instance"
  value       = linode_instance.jumphost.label
}

output "jumphost_password" {
  description = "Root password for the jumphost (emergency use only)"
  value       = random_password.jumphost_password.result
  sensitive   = true
}

output "jumphost_firewall_id" {
  description = "ID of the jumphost firewall"
  value       = linode_firewall.jumphost.id
}

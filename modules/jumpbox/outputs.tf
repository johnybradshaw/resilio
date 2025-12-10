# modules/jumpbox/outputs.tf
output "instance_id" {
  description = "ID of the jumpbox instance"
  value       = linode_instance.jumpbox.id
}

output "ipv4_address" {
  description = "IPv4 address of the jumpbox"
  value       = linode_instance.jumpbox.ip_address
}

output "ipv6_address" {
  description = "IPv6 address of the jumpbox"
  value       = linode_instance.jumpbox.ipv6
}

output "ssh_connection_string" {
  description = "SSH connection string for the jumpbox"
  value       = "ssh ac-user@${linode_instance.jumpbox.ip_address}"
}

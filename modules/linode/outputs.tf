# modules/linode/outputs.tf
output "instance_id" {
  description = "ID of the created Linode instance"
  value       = linode_instance.resilio.id
}

output "instance_label" {
  description = "Label of the created Linode instance"
  value       = linode_instance.resilio.label
}

output "ipv4_address" {
  description = "IPv4 address of the created Linode instance"
  value       = linode_instance.resilio.ipv4
}

output "ipv6_address" {
  description = "IPv6 address of the created Linode instance"
  value       = linode_instance.resilio.ipv6
}

output "root_password" {
  description = "Root password for the Linode instance (keep secure)"
  value       = random_password.root_password.result
  sensitive   = true
}

# modules/linode/outputs.tf
output "instance_id" {
  description = "ID of the created Linode instance"
  value       = linode_instance.resilio.id
}

output "instance_label" {
  description = "Label of the created Linode instance"
  value       = linode_instance.resilio.label
}

output "hostname" {
  description = "Hostname of the instance (matches DNS record, e.g., us-east.resilio-sync)"
  value       = local.hostname
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

output "user_password" {
  description = "Password for ac-user (for console login and sudo)"
  value       = random_password.passwords["user_password"].result
  sensitive   = true
}

output "webui_password" {
  description = "Password for Resilio Sync web UI (username: admin)"
  value       = random_password.passwords["webui_password"].result
  sensitive   = true
}

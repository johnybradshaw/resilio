# modules/firewall/outputs.tf

output "firewall_id" {
  description = "ID of the created firewall"
  value       = linode_firewall.resilio.id
}

output "firewall_label" {
  description = "Label of the created firewall"
  value       = linode_firewall.resilio.label
}

output "firewall_status" {
  description = "Status of the firewall"
  value       = linode_firewall.resilio.status
}

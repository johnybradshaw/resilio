# modules/resilio-firewall/outputs.tf

output "firewall_id" {
  description = "The ID of the resilio firewall"
  value       = linode_firewall.resilio.id
}

output "firewall_label" {
  description = "The label of the resilio firewall"
  value       = linode_firewall.resilio.label
}

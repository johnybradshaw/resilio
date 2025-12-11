# modules/jumpbox-firewall/outputs.tf

output "firewall_id" {
  description = "The ID of the jumpbox firewall"
  value       = linode_firewall.jumpbox.id
}

output "firewall_label" {
  description = "The label of the jumpbox firewall"
  value       = linode_firewall.jumpbox.label
}

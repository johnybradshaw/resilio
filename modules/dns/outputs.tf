# modules/dns/outputs.tf

output "domain_id" {
    description = "ID of the created domain"
    value       = linode_domain.resilio.id
}
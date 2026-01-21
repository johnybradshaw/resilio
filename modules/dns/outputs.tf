# modules/dns/outputs.tf
# Domain-related outputs are now in main.tf where the domain is created

output "dns_records" {
  description = "Map of DNS A records created"
  value = {
    for name, record in linode_domain_record.resilio_A : name => {
      type   = record.record_type
      name   = record.name
      target = record.target
    }
  }
}

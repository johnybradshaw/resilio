# modules/dns/outputs.tf

output "domain_id" {
  description = "ID of the domain (created or existing)"
  value       = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
}

output "nameservers" {
  description = "Nameservers for the domain (configure these at your domain registrar)"
  value = [
    "ns1.linode.com",
    "ns2.linode.com",
    "ns3.linode.com",
    "ns4.linode.com",
    "ns5.linode.com"
  ]
}

output "domain_name" {
  description = "The domain name"
  value       = var.tld
}

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

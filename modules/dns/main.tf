# modules/dns/main.tf

locals {
  # Create a map of label -> IP addresses for stable resource addressing
  dns_records = { for idx, label in var.linode_label : label => {
    ipv4 = var.linode_ipv4[idx]
    ipv6 = var.linode_ipv6[idx]
  }}
}

resource "linode_domain" "resilio" {
  type = "master"
  domain = var.tld
  soa_email = "admin@${var.tld}"
  tags = [ "terraform", "dns", var.project_name ]

  lifecycle {
    # If domain already exists in Linode DNS, import it instead of creating
    # To import: terraform import module.dns.linode_domain.resilio <domain_id>
    # To find domain_id: linode-cli domains list
    prevent_destroy = true
  }
}

resource "linode_domain_record" "resilio_A" {
  for_each    = local.dns_records
  domain_id   = linode_domain.resilio.id
  record_type = "A"
  name        = each.key
  target      = each.value.ipv4
  ttl_sec     = var.ttl_sec
}

resource "linode_domain_record" "resilio_AAAA" {
  for_each    = local.dns_records
  domain_id   = linode_domain.resilio.id
  record_type = "AAAA"
  name        = each.key
  target      = replace(each.value.ipv6, "/128", "")
  ttl_sec     = var.ttl_sec
}
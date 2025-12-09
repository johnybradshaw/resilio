# modules/dns/main.tf

locals {
  # Create a map of label -> IP addresses for stable resource addressing
  dns_records = { for idx, label in var.linode_label : label => {
    ipv4 = var.linode_ipv4[idx]
    ipv6 = var.linode_ipv6[idx]
  }}
}

# Create new domain (if create_domain = true)
resource "linode_domain" "resilio" {
  count = var.create_domain ? 1 : 0

  type = "master"
  domain = var.tld
  soa_email = "admin@${var.tld}"
  tags = [ "terraform", "dns", var.project_name ]

  lifecycle {
    prevent_destroy = true
  }
}

# Use existing domain (if create_domain = false)
data "linode_domain" "existing" {
  count = var.create_domain ? 0 : 1

  domain = var.tld
}

resource "linode_domain_record" "resilio_A" {
  for_each    = local.dns_records
  domain_id   = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
  record_type = "A"
  name        = each.key
  target      = each.value.ipv4
  ttl_sec     = var.ttl_sec
}

resource "linode_domain_record" "resilio_AAAA" {
  for_each    = local.dns_records
  domain_id   = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
  record_type = "AAAA"
  name        = each.key
  target      = replace(each.value.ipv6, "/128", "")
  ttl_sec     = var.ttl_sec
}
# modules/dns/main.tf
# This module creates DNS A/AAAA records for Resilio instances
# The domain itself is created/managed in main.tf to avoid circular dependencies with ACME

# DNS A records - keyed by region (static, known at plan time)
resource "linode_domain_record" "resilio_A" {
  for_each    = var.dns_records
  domain_id   = var.domain_id
  record_type = "A"
  name        = "${each.key}.${var.project_name}" # e.g., "us-east.resilio-sync"
  target      = each.value.ipv4
  ttl_sec     = var.ttl_sec
}

# DNS AAAA records - keyed by region (static, known at plan time)
resource "linode_domain_record" "resilio_AAAA" {
  for_each    = var.dns_records
  domain_id   = var.domain_id
  record_type = "AAAA"
  name        = "${each.key}.${var.project_name}" # e.g., "us-east.resilio-sync"
  target      = replace(each.value.ipv6, "/128", "")
  ttl_sec     = var.ttl_sec
}

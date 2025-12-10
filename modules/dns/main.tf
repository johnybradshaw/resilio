# modules/dns/main.tf

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

# DNS A records - keyed by region (static, known at plan time)
resource "linode_domain_record" "resilio_A" {
  for_each    = var.dns_records
  domain_id   = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
  record_type = "A"
  name        = "${var.project_name}.${each.key}"  # e.g., "resilio-sync.us-east"
  target      = each.value.ipv4
  ttl_sec     = var.ttl_sec
}

# DNS AAAA records - keyed by region (static, known at plan time)
resource "linode_domain_record" "resilio_AAAA" {
  for_each    = var.dns_records
  domain_id   = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
  record_type = "AAAA"
  name        = "${var.project_name}.${each.key}"  # e.g., "resilio-sync.us-east"
  target      = replace(each.value.ipv6, "/128", "")
  ttl_sec     = var.ttl_sec
}
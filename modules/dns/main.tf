# modules/dns/main.tf

resource "linode_domain" "resilio" {
  type = "master"
  domain = var.tld
  soa_email = "admin@${var.tld}"
  tags = [ "terraform", "dns", var.project_name ]
}

resource "linode_domain_record" "resilio_A" {
  count       = length(var.linode_label)
  domain_id   = linode_domain.resilio.id
  record_type = "A"
  name        = var.linode_label[count.index]
  target      = var.linode_ipv4[count.index]
  ttl_sec     = var.ttl_sec
}

resource "linode_domain_record" "resilio_AAAA" {
  count       = length(var.linode_label)
  domain_id   = linode_domain.resilio.id
  record_type = "AAAA"
  name        = var.linode_label[count.index]
  target      = replace(var.linode_ipv6[count.index], "/128", "")
  ttl_sec     = var.ttl_sec
}
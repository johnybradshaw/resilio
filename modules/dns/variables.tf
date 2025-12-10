# modules/dns/variables.tf

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type        = string
}

variable "create_domain" {
  description = "Whether to create the domain or use an existing one. Set to false if domain already exists in Linode DNS."
  type        = bool
  default     = true
}

variable "dns_records" {
  description = "Map of DNS records keyed by region with ipv4 and ipv6 addresses"
  type = map(object({
    ipv4 = string
    ipv6 = string
  }))
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "ttl_sec" {
  description = "TTL in seconds"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

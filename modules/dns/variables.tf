# modules/dns/variables.tf

variable "domain_id" {
  description = "Linode domain ID for creating DNS records"
  type        = number
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

variable "include_project_name" {
  description = "Whether to include project name in DNS record names"
  type        = bool
  default     = true
}

variable "ttl_sec" {
  description = "TTL in seconds"
  type        = number
  default     = 60
}

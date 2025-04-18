# modules/dns/variables.tf

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type = string
}

variable "linode_label" {
  description = "Linode instance labels"
  type        = list(string)
}

variable "linode_ipv4" {
  description = "Linode instance IPv4 addresses"
  type        = list(string)
}

variable "linode_ipv6" {
  description = "Linode instance IPv4 addresses"
  type        = list(string)
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "ttl_sec" {
  description = "TTL in seconds"
  type = number
  default = 60
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}
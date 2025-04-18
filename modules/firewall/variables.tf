# modules/firewall/variables.tf
variable "linode_id" {
  description = "Linode instance IDs"
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

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

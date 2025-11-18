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
  description = "Linode instance IPv6 addresses"
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

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH/ping access (e.g., '1.2.3.4/32')"
  type        = string
  default     = "0.0.0.0/0"  # Default allows all - should be overridden for security
}

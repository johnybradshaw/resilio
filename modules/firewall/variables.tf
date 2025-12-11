# modules/firewall/variables.tf
variable "linode_ipv4" {
  description = "Linode instance IPv4 addresses for inter-instance rules (optional, can be empty initially)"
  type        = list(string)
  default     = []
}

variable "linode_ipv6" {
  description = "Linode instance IPv6 addresses for inter-instance rules (optional, can be empty initially)"
  type        = list(string)
  default     = []
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
  description = "CIDR block allowed for SSH/ping access to jumpbox (e.g., '1.2.3.4/32')"
  type        = string
  default     = "0.0.0.0/0" # Default allows all - should be overridden for security
}

variable "jumpbox_ipv4" {
  description = "Jumpbox IPv4 address for SSH access to resilio instances"
  type        = string
  default     = null
}

variable "jumpbox_ipv6" {
  description = "Jumpbox IPv6 address for SSH access to resilio instances"
  type        = string
  default     = null
}

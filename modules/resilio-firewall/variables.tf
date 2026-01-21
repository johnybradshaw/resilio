# modules/resilio-firewall/variables.tf

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

variable "suffix" {
  description = "Global suffix shared across all resources (from random_id.global_suffix)"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
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

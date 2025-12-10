# modules/jumpbox/variables.tf
variable "region" {
  description = "Linode region for the jumpbox"
  type        = string
}

variable "instance_type" {
  description = "Linode instance type for jumpbox (smaller instance recommended)"
  type        = string
  default     = "g6-nanode-1"  # Smallest Linode instance
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the jumpbox"
  type        = string
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "firewall_id" {
  description = "ID of the firewall to attach to the jumpbox"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

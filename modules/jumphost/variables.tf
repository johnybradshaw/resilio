# modules/jumphost/variables.tf

variable "region" {
  description = "Linode region for jumphost deployment"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for jumphost access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the jumphost"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., '1.2.3.4/32')."
  }
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "tags" {
  description = "Tags to apply to jumphost resources"
  type        = list(string)
  default     = []
}

variable "admin_username" {
  description = "Non-root admin username for SSH access with sudo privileges"
  type        = string
}

# variables.tf
variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "regions" {
  description = "List of Linode regions to deploy to"
  type        = list(string)
  default     = ["us-east", "eu-west"]

  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region must be specified."
  }
}

variable "resilio_folder_key" {
  description = "Resilio Sync folder key to automatically add"
  type        = string
  sensitive   = true
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type = string
  sensitive = true
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instances"
  type        = string
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
  default     = "g6-standard-1"
}

variable "volume_size" {
  description = "Size of the storage volume in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.volume_size >= 10 && var.volume_size <= 10000
    error_message = "Volume size must be between 10 and 10000 GB."
  }
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "resilio-sync"
}

variable "ubuntu_advantage_token" {
  description = "Ubuntu Advantage token"
  type = string
  sensitive = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type = string

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.)+[a-z]{2,}$", var.tld))
    error_message = "TLD must be a valid domain name (e.g., 'example.com' or 'subdomain.example.com')."
  }
}

variable "create_domain" {
  description = "Whether to create the domain in Linode DNS or use an existing one. Set to false if domain already exists."
  type        = bool
  default     = false  # Default to false since most users will have existing domains
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH/ping access to jumpbox (e.g., '1.2.3.4/32')"
  type        = string
  default     = "0.0.0.0/0"  # Default allows all - override with your IP for security

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., '1.2.3.4/32' or '0.0.0.0/0')."
  }
}

variable "jumpbox_region" {
  description = "Linode region for the jumpbox (bastion host)"
  type        = string
  default     = "us-east"
}

variable "jumpbox_instance_type" {
  description = "Linode instance type for the jumpbox"
  type        = string
  default     = "g6-nanode-1"  # Smallest instance (1GB RAM, 1 vCPU) - sufficient for jumpbox
}
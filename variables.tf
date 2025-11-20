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

variable "admin_username" {
  description = "Non-root admin username for SSH access with sudo privileges"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.admin_username)) && var.admin_username != "root"
    error_message = "Admin username must be lowercase, start with a letter or underscore, and cannot be 'root'."
  }
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
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.[a-z]{2,}$", var.tld))
    error_message = "TLD must be a valid domain name (e.g., 'example.com')."
  }
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access to jumphost (e.g., '1.2.3.4/32'). Jumphost provides secure access to Resilio instances."
  type        = string
  default     = "0.0.0.0/0"  # Default allows all - STRONGLY recommend setting to your IP for security

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., '1.2.3.4/32' or '0.0.0.0/0')."
  }
}

variable "enable_jumphost" {
  description = "Enable jumphost for secure SSH access to Resilio instances. When enabled, only jumphost can SSH to Resilio VMs."
  type        = bool
  default     = true
}

variable "jumphost_region" {
  description = "Linode region for jumphost deployment. Defaults to first region in regions list if not specified."
  type        = string
  default     = ""
}
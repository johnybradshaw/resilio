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

# New per-folder volume configuration (recommended)
variable "resilio_folders" {
  description = "Map of Resilio Sync folders with their keys and volume sizes. Each folder gets a dedicated volume."
  type = map(object({
    key  = string # Resilio folder key (sensitive)
    size = number # Volume size in GB
  }))
  sensitive = true
  default   = {}

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name)) && length(name) >= 2 && length(name) <= 32
    ])
    error_message = "Folder names must be 2-32 characters, lowercase alphanumeric with hyphens (no leading/trailing hyphens)."
  }

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      config.size >= 10 && config.size <= 10000
    ])
    error_message = "Volume size must be between 10 and 10000 GB."
  }

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      length(config.key) >= 20
    ])
    error_message = "Resilio folder keys must be at least 20 characters."
  }

  validation {
    condition     = length(keys(var.resilio_folders)) <= 13
    error_message = "Maximum 13 folders per instance (limited by device letters)."
  }
}

# [DEPRECATED] Legacy variables - use resilio_folders instead
variable "resilio_folder_keys" {
  description = "[DEPRECATED] Use resilio_folders instead. List of Resilio Sync folder keys."
  type        = list(string)
  sensitive   = true
  default     = []
}

variable "resilio_folder_key" {
  description = "[DEPRECATED] Use resilio_folders instead. Single Resilio Sync folder key."
  type        = string
  sensitive   = true
  default     = ""
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type        = string
  sensitive   = true
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
  description = "[DEPRECATED] Use per-folder sizes in resilio_folders instead. Default size for legacy single-volume setup."
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
  type        = string
  sensitive   = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.)+[a-z]{2,}$", var.tld))
    error_message = "TLD must be a valid domain name (e.g., 'example.com' or 'subdomain.example.com')."
  }
}

variable "create_domain" {
  description = "Whether to create the domain in Linode DNS or use an existing one. Set to false if domain already exists."
  type        = bool
  default     = false # Default to false since most users will have existing domains
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH/ping access to jumpbox. Defaults to auto-detected current IP. Set to '0.0.0.0/0' to allow all (NOT recommended)."
  type        = string
  default     = null # Will be auto-detected if not specified

  validation {
    condition     = var.allowed_ssh_cidr == null || can(cidrhost(var.allowed_ssh_cidr, 0))
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
  default     = "g6-nanode-1" # Smallest instance (1GB RAM, 1 vCPU) - sufficient for jumpbox
}

variable "object_storage_access_key" {
  description = "Linode Object Storage access key for backups. Set to empty string or 'CHANGEME' to disable backups."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_secret_key" {
  description = "Linode Object Storage secret key for backups"
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_endpoint" {
  description = "Linode Object Storage endpoint (e.g., us-east-1.linodeobjects.com)"
  type        = string
  default     = "us-east-1.linodeobjects.com"
}

variable "object_storage_bucket" {
  description = "Linode Object Storage bucket name for backups"
  type        = string
  default     = "resilio-backups"
}

variable "backup_regions" {
  description = "List of regions that should run Object Storage backups. Only these regions will have backup cron jobs. Empty list disables backups on all regions."
  type        = list(string)
  default     = [] # Set to ["us-east"] to enable backups on one region only
}

variable "cloud_user" {
  description = "Non-root user for SSH access and management"
  type        = string
  default     = "ac-user"
}

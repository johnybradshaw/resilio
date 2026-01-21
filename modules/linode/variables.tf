# modules/linode/variables.tf
variable "region" {
  description = "Linode region"
  type        = string
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instance"
  type        = string
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "suffix" {
  description = "Global suffix shared across all VMs (from random_id.global_suffix)"
  type        = string
}

# New per-folder volume configuration
variable "resilio_folders" {
  description = "Map of folder names to their configurations"
  type = map(object({
    key  = string
    size = number
  }))
  sensitive = true
}

variable "folder_volumes" {
  description = "Map of folder names to volume details (from volume module)"
  type = map(object({
    id     = number
    label  = string
    size   = number
    region = string
  }))
}

# [DEPRECATED] Legacy variables - kept for backward compatibility
variable "volume_id" {
  description = "[DEPRECATED] ID of the volume to attach (use folder_volumes instead)"
  type        = string
  default     = null
}

variable "resilio_folder_keys" {
  description = "[DEPRECATED] List of Resilio Sync folder keys (use resilio_folders instead)"
  type        = list(string)
  sensitive   = true
  default     = []
}

variable "resilio_folder_key" {
  description = "[DEPRECATED] Use resilio_folders instead"
  type        = string
  sensitive   = true
  default     = ""
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type        = string
  sensitive   = true
}

variable "ubuntu_advantage_token" {
  description = "Ubuntu Advantage token"
  type        = string
  sensitive   = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "firewall_id" {
  description = "ID of the firewall to attach to this instance"
  type        = string
}

variable "object_storage_access_key" {
  description = "Linode Object Storage access key for backups"
  type        = string
  sensitive   = true
}

variable "object_storage_secret_key" {
  description = "Linode Object Storage secret key for backups"
  type        = string
  sensitive   = true
}

variable "object_storage_endpoint" {
  description = "Linode Object Storage endpoint"
  type        = string
}

variable "object_storage_bucket" {
  description = "Linode Object Storage bucket name"
  type        = string
}

variable "enable_backup" {
  description = "[LEGACY] Whether to enable Object Storage backups on this instance"
  type        = bool
  default     = false
}

# New backup configuration object
variable "backup_config" {
  description = "Backup configuration object with all backup settings"
  type = object({
    enabled          = bool
    mode             = string # "scheduled", "realtime", or "hybrid"
    schedule         = string # Cron schedule
    transfers        = number # Parallel transfers
    bandwidth_limit  = string # e.g., "10M" or ""
    versioning       = bool
    retention_days   = number
    access_key       = string
    secret_key       = string
    primary_endpoint = string
    primary_bucket   = string
    all_buckets      = map(object({
      name     = string
      cluster  = string
      endpoint = string
      hostname = string
    }))
  })
  sensitive = true
  default = {
    enabled          = false
    mode             = "scheduled"
    schedule         = "0 2 * * *"
    transfers        = 8
    bandwidth_limit  = ""
    versioning       = true
    retention_days   = 90
    access_key       = ""
    secret_key       = ""
    primary_endpoint = ""
    primary_bucket   = ""
    all_buckets      = {}
  }
}

# SSL certificate variables for Resilio HTTPS
variable "ssl_certificate" {
  description = "Let's Encrypt SSL certificate (PEM format)"
  type        = string
  sensitive   = true
}

variable "ssl_private_key" {
  description = "SSL certificate private key (PEM format)"
  type        = string
  sensitive   = true
}

variable "ssl_issuer_cert" {
  description = "SSL issuer/CA certificate (PEM format)"
  type        = string
  sensitive   = true
}

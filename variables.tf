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

variable "acme_server_url" {
  description = "ACME server URL for Let's Encrypt certificates. Use staging for testing to avoid rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  # Staging URL: "https://acme-staging-v02.api.letsencrypt.org/directory"
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

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

variable "backup_enabled" {
  description = "Enable Object Storage backups. When true, Terraform will create and manage backup buckets and keys."
  type        = bool
  default     = false
}

variable "backup_storage_regions" {
  description = "List of Linode Object Storage regions for backup destinations. Note: Object Storage uses different region IDs than compute (e.g., 'us-east-1' not 'us-east')."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition = alltrue([
      for region in var.backup_storage_regions :
      contains([
        "us-east-1",      # Newark, NJ
        "us-southeast-1", # Atlanta, GA
        "us-iad-1",       # Washington, DC
        "us-ord-1",       # Chicago, IL
        "us-sea-1",       # Seattle, WA
        "eu-central-1",   # Frankfurt, Germany
        "fr-par-1",       # Paris, France
        "se-sto-1",       # Stockholm, Sweden
        "ap-south-1",     # Singapore
        "jp-osa-1",       # Osaka, Japan
        "in-maa-1",       # Chennai, India
        "id-cgk-1",       # Jakarta, Indonesia
        "br-gru-1",       # São Paulo, Brazil
        "au-mel-1",       # Melbourne, Australia
      ], region)
    ])
    error_message = "Invalid Object Storage region. Valid regions: us-east-1, us-southeast-1, us-iad-1, us-ord-1, us-sea-1, eu-central-1, fr-par-1, se-sto-1, ap-south-1, jp-osa-1, in-maa-1, id-cgk-1, br-gru-1, au-mel-1. Note: Object Storage regions differ from compute regions."
  }
}

variable "backup_source_regions" {
  description = "List of VM regions that should run backups. Only VMs in these regions will push to Object Storage. Empty = no VMs backup. For efficiency, recommend only one region since all VMs sync the same data."
  type        = list(string)
  default     = [] # Set to ["us-east"] to have one region backup
}

variable "backup_versioning" {
  description = "Enable object versioning for backup buckets (recommended for data protection and recovery)"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backup versions. Old versions are automatically cleaned up. Set to 0 to keep forever."
  type        = number
  default     = 90

  validation {
    condition     = var.backup_retention_days >= 0
    error_message = "Retention days must be 0 or greater."
  }
}

variable "backup_mode" {
  description = "Backup scheduling mode: 'scheduled' (cron-based), 'realtime' (inotify-based immediate sync), or 'hybrid' (realtime + daily full sync)"
  type        = string
  default     = "scheduled"

  validation {
    condition     = contains(["scheduled", "realtime", "hybrid"], var.backup_mode)
    error_message = "Backup mode must be 'scheduled', 'realtime', or 'hybrid'."
  }
}

variable "backup_schedule" {
  description = "Cron schedule for backups (used in 'scheduled' and 'hybrid' modes). Default: daily at 2 AM."
  type        = string
  default     = "0 2 * * *"
}

variable "backup_transfers" {
  description = "Number of parallel file transfers for rclone (higher = faster but more CPU/IO)"
  type        = number
  default     = 8

  validation {
    condition     = var.backup_transfers >= 1 && var.backup_transfers <= 32
    error_message = "Backup transfers must be between 1 and 32."
  }
}

variable "backup_bandwidth_limit" {
  description = "Bandwidth limit for backups in bytes/sec (e.g., '10M' for 10MB/s). Empty string = unlimited."
  type        = string
  default     = ""
}

variable "backup_bucket_prefix" {
  description = "Prefix for backup bucket names (will be suffixed with region)"
  type        = string
  default     = "resilio-backup"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.backup_bucket_prefix)) || var.backup_bucket_prefix == ""
    error_message = "Bucket prefix must be lowercase alphanumeric with hyphens."
  }
}

# Legacy variables - kept for backward compatibility
# These are used if backup_enabled = false and manual credentials are provided
variable "object_storage_access_key" {
  description = "[LEGACY] Manual Object Storage access key. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_secret_key" {
  description = "[LEGACY] Manual Object Storage secret key. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_endpoint" {
  description = "[LEGACY] Manual Object Storage endpoint. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  default     = "us-east-1.linodeobjects.com"
}

variable "object_storage_bucket" {
  description = "[LEGACY] Manual Object Storage bucket. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  default     = "resilio-backups"
}

variable "backup_regions" {
  description = "[DEPRECATED] Use backup_source_regions instead. List of VM regions that should run backups."
  type        = list(string)
  default     = []
}

variable "cloud_user" {
  description = "Non-root user for SSH access and management"
  type        = string
  default     = "ac-user"
}

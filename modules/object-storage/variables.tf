# modules/object-storage/variables.tf

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "suffix" {
  description = "Global suffix for resource naming"
  type        = string
}

variable "bucket_prefix" {
  description = "Prefix for bucket names (will be suffixed with region)"
  type        = string
  default     = "resilio-backup"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must be lowercase alphanumeric with hyphens, no leading/trailing hyphens."
  }
}

variable "backup_regions" {
  description = "List of Linode regions for backup storage (e.g., ['us-east', 'eu-west'])"
  type        = list(string)

  validation {
    condition     = length(var.backup_regions) > 0
    error_message = "At least one backup region must be specified."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning for backup buckets (recommended for data protection)"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain backup versions (0 = keep forever)"
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days >= 0
    error_message = "Retention days must be 0 or greater."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = list(string)
  default     = []
}

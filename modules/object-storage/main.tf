# modules/object-storage/main.tf
# Manages Linode Object Storage for Resilio Sync backups

# Object Storage bucket for backups
# One bucket per backup region for redundancy and performance
resource "linode_object_storage_bucket" "backup" {
  for_each = toset(var.backup_regions)

  region     = each.key # e.g., "us-east", "eu-west"
  label      = "${var.bucket_prefix}-${each.key}"
  acl        = "private"
  versioning = var.enable_versioning

  # CORS configuration for potential web access
  cors_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}

# Object Storage access key - one per bucket to avoid dynamic block provider bug
resource "linode_object_storage_key" "backup" {
  for_each = linode_object_storage_bucket.backup

  label = "${var.project_name}-backup-key-${each.key}-${var.suffix}"

  bucket_access {
    bucket_name = each.value.label
    region      = each.value.region
    permissions = "read_write"
  }
}

# Lifecycle policy for backup retention
# Applied via rclone configuration since Linode doesn't have native lifecycle rules
# This is handled in the backup script with --max-age flags

# Local values for bucket endpoints
locals {
  # Map of region to bucket details
  # Object Storage region IDs already include the suffix (e.g., us-east-1)
  bucket_details = {
    for region, bucket in linode_object_storage_bucket.backup : region => {
      name     = bucket.label
      cluster  = bucket.region # Region ID is already in correct format (e.g., us-east-1)
      endpoint = "${bucket.region}.linodeobjects.com"
      hostname = bucket.hostname
    }
  }

  # Primary bucket (first in alphabetical order for consistency)
  primary_region   = sort(var.backup_regions)[0]
  primary_bucket   = local.bucket_details[local.primary_region]
  primary_endpoint = local.primary_bucket.endpoint
}

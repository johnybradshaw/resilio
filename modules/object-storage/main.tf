# modules/object-storage/main.tf
# Manages Linode Object Storage for Resilio Sync backups

# Object Storage bucket for backups
# One bucket per backup region for redundancy and performance
resource "linode_object_storage_bucket" "backup" {
  for_each = toset(var.backup_regions)

  cluster    = "${each.key}-1" # e.g., "us-east-1", "eu-west-1"
  label      = "${var.bucket_prefix}-${each.key}"
  acl        = "private"
  versioning = var.enable_versioning

  # CORS configuration for potential web access
  cors_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}

# Object Storage access key with limited scope
# This key only has access to the backup buckets
resource "linode_object_storage_key" "backup" {
  label = "${var.project_name}-backup-key-${var.suffix}"

  # Grant read/write access to all backup buckets
  dynamic "bucket_access" {
    for_each = linode_object_storage_bucket.backup
    content {
      cluster     = bucket_access.value.cluster
      bucket_name = bucket_access.value.label
      permissions = "read_write"
    }
  }
}

# Lifecycle policy for backup retention
# Applied via rclone configuration since Linode doesn't have native lifecycle rules
# This is handled in the backup script with --max-age flags

# Local values for bucket endpoints
locals {
  # Map of region to bucket details
  bucket_details = {
    for region, bucket in linode_object_storage_bucket.backup : region => {
      name     = bucket.label
      cluster  = bucket.cluster
      endpoint = "${bucket.cluster}.linodeobjects.com"
      hostname = bucket.hostname
    }
  }

  # Primary bucket (first in alphabetical order for consistency)
  primary_region   = sort(var.backup_regions)[0]
  primary_bucket   = local.bucket_details[local.primary_region]
  primary_endpoint = local.primary_bucket.endpoint
}

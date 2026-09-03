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

  # Note: prevent_destroy is intentionally NOT set here because:
  # 1. It blocks legitimate operations like changing backup_storage_regions
  # 2. Terraform plan/apply workflow already requires explicit approval
  # 3. Object versioning (enabled by default) protects against data loss
  # 4. Buckets with objects cannot be deleted without first emptying them
  # To protect against accidental deletion, use CI/CD approval workflows
}

# Object Storage access key (limited to backup buckets only)
resource "linode_object_storage_key" "backup" {
  label = "${var.project_name}-backup-key-${var.suffix}"

  dynamic "bucket_access" {
    for_each = linode_object_storage_bucket.backup
    content {
      bucket_name = bucket_access.value.label
      region      = bucket_access.value.region
      permissions = "read_write"
    }
  }
}

# Lifecycle policy for backup retention
# Applied via rclone configuration since Linode doesn't have native lifecycle rules
# This is handled in the backup script with --max-age flags

# Local values for bucket endpoints
locals {
  # The API's `region` attribute is the COMPUTE region id ("us-east"), but the
  # S3 endpoint needs the CLUSTER id ("us-east-1"). Assembling the endpoint as
  # "${bucket.region}.linodeobjects.com" therefore produced the INVALID host
  # "us-east.linodeobjects.com" and every backup failed to resolve.
  #
  # Derive it from the bucket's own hostname instead of assembling it, so it is
  # correct whichever form the provider returns:
  #   <label>.<cluster>.linodeobjects.com  ->  <cluster>.linodeobjects.com
  bucket_endpoints = {
    for region, bucket in linode_object_storage_bucket.backup :
    region => replace(bucket.hostname, "${bucket.label}.", "")
  }

  # Map of region to bucket details
  bucket_details = {
    for region, bucket in linode_object_storage_bucket.backup : region => {
      name     = bucket.label
      cluster  = split(".", local.bucket_endpoints[region])[0]
      endpoint = local.bucket_endpoints[region]
      hostname = bucket.hostname
    }
  }

  # Primary bucket (first in alphabetical order for consistency).
  #
  # These must tolerate bucket_details being EMPTY. A hard index here made the
  # configuration unable to recover from its own broken state: once the buckets
  # were deleted out-of-band, `terraform refresh` could not complete, which is
  # exactly the operation needed to notice the deletion and recreate them.
  # Deadlocks like that are worse than a transiently empty value, which the
  # consumers in main.tf already guard with `length(module.backup_storage) > 0`.
  primary_region = length(var.backup_regions) > 0 ? sort(var.backup_regions)[0] : ""
  primary_bucket = try(local.bucket_details[local.primary_region], {
    name     = ""
    cluster  = ""
    endpoint = ""
    hostname = ""
  })
  primary_endpoint = local.primary_bucket.endpoint
}

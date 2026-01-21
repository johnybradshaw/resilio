# modules/object-storage/outputs.tf

# Primary key (for backward compatibility - uses first region alphabetically)
output "access_key" {
  description = "Primary Object Storage access key ID (first region)"
  value       = linode_object_storage_key.backup[local.primary_region].access_key
  sensitive   = true
}

output "secret_key" {
  description = "Primary Object Storage secret key (first region)"
  value       = linode_object_storage_key.backup[local.primary_region].secret_key
  sensitive   = true
}

# All keys by region
output "access_keys" {
  description = "Map of Object Storage access keys by region"
  value = {
    for region, key in linode_object_storage_key.backup : region => key.access_key
  }
  sensitive = true
}

output "secret_keys" {
  description = "Map of Object Storage secret keys by region"
  value = {
    for region, key in linode_object_storage_key.backup : region => key.secret_key
  }
  sensitive = true
}

output "buckets" {
  description = "Map of backup buckets by region"
  value       = local.bucket_details
}

output "primary_bucket" {
  description = "Primary backup bucket details (first region alphabetically)"
  value       = local.primary_bucket
}

output "primary_endpoint" {
  description = "Primary Object Storage endpoint URL"
  value       = local.primary_endpoint
}

output "bucket_names" {
  description = "List of all backup bucket names"
  value       = [for bucket in linode_object_storage_bucket.backup : bucket.label]
}

output "key_ids" {
  description = "Map of Object Storage key IDs by region"
  value = {
    for region, key in linode_object_storage_key.backup : region => key.id
  }
}

output "rclone_remotes" {
  description = "Map of rclone remote configurations by region"
  value = {
    for region, details in local.bucket_details : region => {
      remote_name = "backup-${region}"
      endpoint    = details.endpoint
      bucket      = details.name
    }
  }
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on backup buckets"
  value       = var.enable_versioning
}

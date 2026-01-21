# modules/object-storage/outputs.tf

output "access_key" {
  description = "Object Storage access key ID"
  value       = linode_object_storage_key.backup.access_key
  sensitive   = true
}

output "secret_key" {
  description = "Object Storage secret key"
  value       = linode_object_storage_key.backup.secret_key
  sensitive   = true
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

output "key_id" {
  description = "Object Storage key ID"
  value       = linode_object_storage_key.backup.id
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

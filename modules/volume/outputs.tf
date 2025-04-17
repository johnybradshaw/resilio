# modules/volume/outputs.tf
output "volume_id" {
  description = "ID of the created volume"
  value       = linode_volume.storage.id
}
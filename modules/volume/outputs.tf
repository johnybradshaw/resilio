# modules/volume/outputs.tf

output "volumes" {
  description = "Map of folder names to volume details"
  value = {
    for name, vol in linode_volume.storage : name => {
      id     = vol.id
      label  = vol.label
      size   = vol.size
      region = vol.region
    }
  }
}

# Keep for backward compatibility during migration
output "volume_id" {
  description = "[DEPRECATED] ID of the first volume (for backward compatibility)"
  value       = length(linode_volume.storage) > 0 ? values(linode_volume.storage)[0].id : null
}

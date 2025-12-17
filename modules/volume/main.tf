# modules/volume/main.tf
resource "linode_volume" "storage" {
  label  = "${var.project_name}-${var.region}-vol"
  region = var.region
  size   = var.size
  tags = concat(
    var.tags, [
      "region: ${var.region}", # e.g. "region: us-east"
      "service: blk"           # e.g. "service: storage"
    ]
  )

  lifecycle {
    # SAFETY: Prevent accidental deletion of volumes
    prevent_destroy = true

    # SAFETY: Prevent volume from being recreated if label or region changes
    # This ensures the volume is never destroyed and recreated, which would cause data loss
    ignore_changes = [label, region]

    # IMPORTANT: Volume size can only be INCREASED, never decreased
    # Attempting to decrease volume size will require manual intervention
    # To resize: 1) Update var.volume_size, 2) Run terraform apply
    # The volume will be expanded online without downtime
    # After expansion, you must resize the filesystem manually:
    #   sudo resize2fs /dev/disk/by-label/resilio
  }

  # encryption = "enabled" # Not available in every region
}

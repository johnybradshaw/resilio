# modules/volume/main.tf
# Creates one volume per folder with independent sizing

resource "linode_volume" "storage" {
  for_each = var.folders

  label  = "${var.project_name}-${var.region}-${each.key}"
  region = var.region
  size   = each.value.size
  tags = concat(
    var.tags, [
      "region: ${var.region}",
      "service: blk",
      "folder: ${each.key}"
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
    # To resize: 1) Update the folder's size in resilio_folders, 2) Run terraform apply
    # The volume will be expanded online without downtime
    # Filesystem auto-expands on next boot via volume-auto-expand.service
  }

  # encryption = "enabled" # Not available in every region
}

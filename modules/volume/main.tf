# modules/volume/main.tf
resource "linode_volume" "storage" {
  label  = "${var.project_name}-${var.region}-storage"
  region = var.region
  size   = var.size
  tags = concat(
    var.tags, [
      "region: ${var.region}", # e.g. "region: us-east"
      "service: blk"           # e.g. "service: storage"
    ]
  )

  lifecycle {
    prevent_destroy = true # Prevent deletion
  }

  # encryption = "enabled" # Not available in every region
}

# modules/volume/main.tf
resource "linode_volume" "storage" {
  label  = "${var.project_name}-storage-${var.region}"
  region = var.region
  size   = var.size
  tags   = ["terraform", "${var.project_name}", var.region]
  
  # encryption = "enabled" # Not available in every region
}
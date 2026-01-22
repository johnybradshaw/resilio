# tags.tf
locals {
  tags = concat(
    var.tags, [
      "tld: ${var.tld}",                       # e.g. "tld: test.com"
      "project: ${var.project_name}",          # e.g. "project: resilio-sync"
      "user: ${var.cloud_user}",               # e.g. "user: ac-user"
      "suffix: ${random_id.global_suffix.hex}" # e.g. "suffix: a1b2c3d4" - shared across all VMs
    ]
  )
}

# tags.tf
locals {
  tags = concat(
    var.tags, [
      "tld: ${var.tld}",             # e.g. "tld: test.com"
      "project: ${var.project_name}" # e.g. "project: resilio-sync"
    ]
  )
}

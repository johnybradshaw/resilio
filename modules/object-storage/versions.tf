# modules/object-storage/versions.tf

terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = ">= 2.0"
    }
  }
  required_version = ">= 1.5.0"
}

# providers.tf
terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = ">= 2.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.1"
    }
  }
  required_version = ">= 1.0.0"
}
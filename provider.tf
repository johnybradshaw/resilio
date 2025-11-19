# provider.tf
terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.1"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
  }
  required_version = "~> 1.10"
}

provider "linode" {
  token = var.linode_token
}
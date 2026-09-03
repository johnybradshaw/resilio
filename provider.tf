# provider.tf
terraform {
  # Remote state: Linode Object Storage (S3-compatible).
  #
  # PARTIAL CONFIGURATION — deliberately empty. Bucket, region and endpoint
  # live in backend.tfvars, which is gitignored, so this public repository
  # carries no infrastructure detail. Credentials come from the environment.
  #
  #   source scripts/setup-backend-credentials.sh
  #   terraform init -backend-config=backend.tfvars
  #
  # See docs/BACKEND_SETUP.md. Copy backend.tfvars.example to get started.
  backend "s3" {}

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 4.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.21"
    }
  }
  required_version = ">= 1.5.0"
}

provider "linode" {
  token             = var.linode_token
  obj_use_temp_keys = true # Generate temporary keys for Object Storage operations
}

# ACME provider for Let's Encrypt certificates
# Default: production. Set var.acme_server_url to staging for testing.
provider "acme" {
  server_url = var.acme_server_url
}

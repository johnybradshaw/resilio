# provider.tf
terraform {
  # Backend configuration for Linode Object Storage (S3-compatible)
  # To enable, uncomment and configure the backend block below
  # backend "s3" {
  #   bucket = "terraform-state-resilio"           # Your Linode Object Storage bucket name
  #   key    = "resilio/terraform.tfstate"         # Path to state file within bucket
  #   region = "us-east-1"                         # Linode region (us-east-1, eu-central-1, etc.)
  #
  #   # Linode Object Storage endpoint (adjust region as needed)
  #   endpoint = "https://us-east-1.linodeobjects.com"
  #
  #   # Skip AWS-specific checks
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #
  #   # S3-compatible settings
  #   force_path_style = true
  #
  #   # Server-side encryption with customer-provided key (SSE-C)
  #   # The encryption key should be a 256-bit (32-byte) AES key, base64-encoded
  #   # Use 1Password CLI to retrieve the key:
  #   # export TF_VAR_backend_encryption_key=$(op read "op://vault/terraform-state-key/encryption_key")
  #   # encrypt = true
  #   # kms_key_id = "alias/terraform-state"  # Optional: use KMS if available
  #
  #   # Access credentials - use 1Password to securely store and retrieve
  #   # Set via environment variables:
  #   # export AWS_ACCESS_KEY_ID=$(op read "op://vault/linode-object-storage/access_key_id")
  #   # export AWS_SECRET_ACCESS_KEY=$(op read "op://vault/linode-object-storage/secret_access_key")
  # }

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.6"
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

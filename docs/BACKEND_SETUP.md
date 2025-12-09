# Terraform Backend Setup with Linode Object Storage

This document explains how to configure Terraform to use Linode Object Storage as a remote backend with encryption, integrated with 1Password for secure credential management.

## Overview

The Terraform configuration supports using Linode Object Storage (S3-compatible) as a remote backend to store state files. This provides:

- **Remote state storage**: Share state across team members
- **State locking**: Prevent concurrent modifications
- **Encryption**: Protect sensitive state data
- **1Password integration**: Securely manage credentials

## Prerequisites

1. **Linode Object Storage**
   - Create an Object Storage bucket in Linode Cloud Manager
   - Generate Access Key and Secret Key
   - Note your region (e.g., `us-east-1`, `eu-central-1`)

2. **1Password CLI**
   - Install: https://developer.1password.com/docs/cli/get-started/
   - Sign in: `op signin`

3. **Terraform** >= 1.5.0

## Setup Instructions

### Step 1: Create Linode Object Storage Bucket

1. Log in to [Linode Cloud Manager](https://cloud.linode.com/)
2. Navigate to **Object Storage**
3. Click **Create Bucket**
4. Choose a region and bucket name (e.g., `terraform-state-resilio`)
5. Click **Create Bucket**

### Step 2: Generate Access Keys

1. In Object Storage, click **Access Keys**
2. Click **Create Access Key**
3. Label it (e.g., "Terraform Backend")
4. Save the **Access Key** and **Secret Key** securely

### Step 3: Store Credentials in 1Password

#### Option A: Using 1Password App

1. Create a new item in 1Password:
   - **Title**: `linode-object-storage`
   - **Vault**: `Infrastructure` (or your preferred vault)
   - **Type**: API Credential or Password

2. Add the following fields:
   - `access_key_id`: Your Linode Object Storage access key
   - `secret_access_key`: Your Linode Object Storage secret key

3. (Optional) Create another item for encryption:
   - **Title**: `terraform-state-encryption`
   - **Vault**: `Infrastructure`
   - Add field `encryption_key`: A 256-bit base64-encoded key

#### Option B: Using 1Password CLI

```bash
# Store Object Storage credentials
op item create \
  --category="API Credential" \
  --title="linode-object-storage" \
  --vault="Infrastructure" \
  access_key_id="YOUR_ACCESS_KEY" \
  secret_access_key="YOUR_SECRET_KEY"

# Generate and store encryption key
ENCRYPTION_KEY=$(openssl rand -base64 32)
op item create \
  --category="Password" \
  --title="terraform-state-encryption" \
  --vault="Infrastructure" \
  encryption_key="${ENCRYPTION_KEY}"
```

### Step 4: Configure Backend in provider.tf

1. Open `provider.tf`
2. Uncomment the `backend "s3"` block
3. Update the configuration values:
   - `bucket`: Your bucket name
   - `key`: Path to state file (e.g., `resilio/terraform.tfstate`)
   - `region`: Your Linode region
   - `endpoint`: Your region's endpoint (e.g., `https://us-east-1.linodeobjects.com`)

Example configuration:

```hcl
backend "s3" {
  bucket = "terraform-state-resilio"
  key    = "resilio/terraform.tfstate"
  region = "us-east-1"

  endpoint = "https://us-east-1.linodeobjects.com"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  force_path_style = true

  # Optional: Enable encryption
  encrypt = true
}
```

### Step 5: Load Credentials and Initialize

```bash
# Load credentials from 1Password
source scripts/setup-backend-credentials.sh

# Initialize Terraform with the new backend
terraform init

# Verify backend configuration
terraform state list
```

## Usage

### Daily Workflow

Every time you work with Terraform, load the credentials first:

```bash
# Load credentials
source scripts/setup-backend-credentials.sh

# Run Terraform commands
terraform plan
terraform apply
```

### Customizing 1Password Setup

If you use different vault names or item names, set these environment variables:

```bash
export OP_VAULT_NAME="YourVaultName"
export OP_OBJECT_STORAGE_ITEM="your-item-name"
export OP_ENCRYPTION_ITEM="your-encryption-item"

source scripts/setup-backend-credentials.sh
```

## Encryption Options

### Option 1: Default S3 Encryption (Recommended)

Set `encrypt = true` in the backend configuration. Linode Object Storage will handle encryption at rest.

```hcl
backend "s3" {
  # ... other config ...
  encrypt = true
}
```

### Option 2: Customer-Provided Encryption Key (SSE-C)

For additional security, provide your own encryption key:

1. Generate a 256-bit key:
   ```bash
   openssl rand -base64 32
   ```

2. Store it in 1Password (see Step 3)

3. Modify `scripts/setup-backend-credentials.sh` to export the key:
   ```bash
   export TF_VAR_backend_encryption_key=$(op read "op://Infrastructure/terraform-state-encryption/encryption_key")
   ```

4. Update backend config to use the key (implementation varies by provider)

## Available Linode Object Storage Regions

- `us-east-1`: Newark, NJ
- `us-southeast-1`: Atlanta, GA
- `eu-central-1`: Frankfurt, Germany
- `ap-south-1`: Singapore

Update the `endpoint` in your backend configuration accordingly:
- `https://us-east-1.linodeobjects.com`
- `https://us-southeast-1.linodeobjects.com`
- `https://eu-central-1.linodeobjects.com`
- `https://ap-south-1.linodeobjects.com`

## Migrating Existing State

If you already have a local state file:

```bash
# Load credentials
source scripts/setup-backend-credentials.sh

# Uncomment and configure backend in provider.tf

# Initialize and migrate
terraform init -migrate-state

# Terraform will prompt to copy existing state to the new backend
# Answer "yes" to proceed
```

## Troubleshooting

### Authentication Errors

**Problem**: "Error: error configuring S3 Backend: no valid credential sources found"

**Solution**:
- Ensure you've run `source scripts/setup-backend-credentials.sh`
- Verify credentials in 1Password: `op read "op://Infrastructure/linode-object-storage/access_key_id"`
- Check that you're signed in to 1Password: `op account list`

### Bucket Access Errors

**Problem**: "Error: error listing S3 Bucket Objects: NoSuchBucket"

**Solution**:
- Verify the bucket name in `provider.tf` matches your Linode bucket
- Ensure the bucket exists in the correct region
- Check endpoint URL matches your region

### Encryption Errors

**Problem**: State file cannot be decrypted

**Solution**:
- Ensure the same encryption key is used consistently
- Don't lose the encryption key stored in 1Password
- Consider backing up the 1Password item

## Security Best Practices

1. **Never commit credentials** to version control
2. **Rotate access keys** regularly in Linode Cloud Manager
3. **Use separate buckets** for different environments (dev/staging/prod)
4. **Enable bucket versioning** to protect against accidental deletions
5. **Restrict bucket access** using Linode's access control features
6. **Backup 1Password vault** regularly
7. **Use different encryption keys** for different environments

## State Locking

Note: Linode Object Storage doesn't support native state locking like AWS DynamoDB. For team environments, consider:

- Using Terraform Cloud for state management
- Implementing a custom locking mechanism
- Coordinating state operations through CI/CD pipelines
- Using `-lock=false` flag cautiously when needed

## Additional Resources

- [Linode Object Storage Documentation](https://www.linode.com/docs/products/storage/object-storage/)
- [Terraform S3 Backend Documentation](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [Terraform State Management Best Practices](https://www.terraform.io/docs/language/state/index.html)

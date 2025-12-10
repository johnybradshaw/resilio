# Initial Setup Guide

This guide walks you through setting up this repository for the first time.

## Quick Start (For New Clones)

When you first clone this repository, run these commands:

```bash
# 1. Clone the repository
git clone https://github.com/johnybradshaw/resilio.git
cd resilio

# 2. Copy and configure your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize Terraform
terraform init

# 4. Verify everything is working
terraform validate
terraform plan
```

That's it! The repository is already configured with:
- ✅ Correct provider versions in all modules
- ✅ Lock file with proper provider versions
- ✅ Pre-configured backend support (optional)

## Understanding the Lock File

### What is `.terraform.lock.hcl`?

The lock file ensures everyone uses the same provider versions. It's committed to the repository intentionally.

**Benefits:**
- Consistent provider versions across team members
- Prevents unexpected provider updates
- Faster `terraform init` (doesn't need to resolve versions)

**When to update it:**
- After updating provider version constraints in `provider.tf` or module `versions.tf` files
- When explicitly upgrading providers

### How to Update the Lock File

If you need to update provider versions:

```bash
# Option 1: Use the provided script (recommended)
bash scripts/regenerate-lockfile.sh

# Option 2: Manual update
rm .terraform.lock.hcl
terraform init -upgrade
git add .terraform.lock.hcl
git commit -m "Update provider lock file"
```

## First-Time Repository Configuration

### Prerequisites

Install these tools before starting:

1. **Terraform** >= 1.5.0
   ```bash
   # Check version
   terraform version

   # Install from: https://www.terraform.io/downloads
   ```

2. **Linode CLI** (optional but recommended)
   ```bash
   pip install linode-cli
   linode-cli configure
   ```

3. **1Password CLI** (optional, for backend)
   ```bash
   # Install from: https://developer.1password.com/docs/cli/get-started/
   ```

4. **Pre-commit** (optional, for contributors)
   ```bash
   pip install pre-commit
   pre-commit install
   ```

### Configuration Steps

#### 1. Set Up Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required
linode_token        = "your-linode-api-token"
ssh_public_key      = "ssh-rsa AAAA..."
resilio_folder_key  = "your-resilio-folder-key"
resilio_license_key = "your-resilio-license"
tld                 = "example.com"

# Optional but recommended
ubuntu_advantage_token = "your-ubuntu-pro-token"
allowed_ssh_cidr       = "YOUR_IP/32"  # Your IP for SSH access

# Optional customization
regions       = ["us-east", "eu-west"]
instance_type = "g6-standard-1"
volume_size   = 50
```

#### 2. (Optional) Set Up Remote Backend

If using Linode Object Storage backend:

```bash
# Follow the backend setup guide
cat docs/BACKEND_SETUP.md

# Quick setup:
# 1. Create bucket in Linode Cloud Manager
# 2. Store credentials in 1Password
# 3. Uncomment backend block in provider.tf
# 4. Load credentials
source scripts/setup-backend-credentials.sh

# 5. Initialize with backend
terraform init
```

#### 3. Initialize Terraform

```bash
# Standard initialization
terraform init

# If you encounter provider issues
bash scripts/fix-provider-lock.sh --clean

# Verify providers are correct
terraform providers
```

Expected output:
```
Providers required by configuration:
.
├── provider[registry.terraform.io/linode/linode] ~> 3.5.0
├── provider[registry.terraform.io/hashicorp/random] >= 3.7.1
└── provider[registry.terraform.io/hashicorp/http] >= 3.4.0
```

#### 4. Validate Configuration

```bash
# Validate syntax and configuration
terraform validate

# Check formatting
terraform fmt -check -recursive

# Preview changes
terraform plan
```

#### 5. Deploy Infrastructure

```bash
# Deploy everything
terraform apply

# Or deploy with auto-approve (use cautiously)
terraform apply -auto-approve
```

## Common Setup Issues

### Issue: Provider Lock File Mismatch

**Error:**
```
locked provider does not match configured version constraint
```

**Fix:**
```bash
bash scripts/fix-provider-lock.sh --clean
```

### Issue: Missing Variables

**Error:**
```
Error: No value for required variable
```

**Fix:**
Ensure all required variables are set in `terraform.tfvars`:
- linode_token
- ssh_public_key
- resilio_folder_key
- resilio_license_key
- tld
- ubuntu_advantage_token

### Issue: Backend Authentication

**Error:**
```
Error: error configuring S3 Backend: no valid credential sources
```

**Fix:**
```bash
# Load credentials from 1Password
source scripts/setup-backend-credentials.sh

# Or set manually
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

## Project Structure Overview

```
resilio/
├── main.tf                          # Root module
├── provider.tf                      # Provider and backend config
├── variables.tf                     # Input variables
├── outputs.tf                       # Outputs
├── terraform.tfvars                 # Your values (not in git)
├── .terraform.lock.hcl              # Provider lock file (in git)
│
├── modules/                         # Reusable modules
│   ├── linode/versions.tf          # Provider requirements
│   ├── volume/versions.tf
│   ├── firewall/versions.tf
│   └── dns/versions.tf
│
├── scripts/                         # Helper scripts
│   ├── setup-backend-credentials.sh
│   ├── fix-provider-lock.sh
│   └── regenerate-lockfile.sh
│
└── docs/                            # Documentation
    ├── SETUP.md                    # This file
    ├── BACKEND_SETUP.md
    └── TROUBLESHOOTING.md
```

## Best Practices

### 1. Never Commit Secrets

The `.gitignore` file is configured to exclude:
- `terraform.tfvars` - Contains your secrets
- `*.tfstate` - May contain sensitive data
- `.terraform/` - Cached providers and modules

### 2. Use Remote State (Recommended)

For team environments, configure remote state:
- See [docs/BACKEND_SETUP.md](BACKEND_SETUP.md)
- Options: Linode Object Storage, Terraform Cloud, S3, GCS, Azure

### 3. Version Control Lock File

The `.terraform.lock.hcl` **should be committed** to ensure:
- Consistent provider versions across team
- Reproducible deployments
- Faster initialization

### 4. Use Pre-commit Hooks

For contributors:
```bash
pre-commit install
pre-commit run --all-files
```

This runs:
- Terraform fmt
- Terraform validate
- TFLint
- Secret scanning

### 5. Review Plans Before Apply

Always review the plan:
```bash
# Save plan to file
terraform plan -out=tfplan

# Review the plan
terraform show tfplan

# Apply the reviewed plan
terraform apply tfplan
```

## Development Workflow

### Making Changes

```bash
# 1. Create a branch
git checkout -b feature/my-change

# 2. Make your changes
# Edit .tf files

# 3. Format code
terraform fmt -recursive

# 4. Validate
terraform validate

# 5. Test plan
terraform plan

# 6. Commit changes
git add .
git commit -m "Description of changes"

# 7. Push and create PR
git push origin feature/my-change
```

### Updating Provider Versions

```bash
# 1. Update version constraints
# Edit provider.tf or module versions.tf files

# 2. Regenerate lock file
bash scripts/regenerate-lockfile.sh

# 3. Test the changes
terraform plan

# 4. Commit both changes
git add provider.tf .terraform.lock.hcl
git commit -m "Update provider versions"
```

## Team Setup

### For Team Members

When joining the team:

1. **Get access to secrets**
   - Ask team lead for access to 1Password vault
   - Get Linode API token
   - Get Resilio Sync keys

2. **Clone and configure**
   ```bash
   git clone https://github.com/johnybradshaw/resilio.git
   cd resilio
   cp terraform.tfvars.example terraform.tfvars
   # Add your credentials
   ```

3. **Load backend credentials**
   ```bash
   source scripts/setup-backend-credentials.sh
   terraform init
   ```

4. **Verify access**
   ```bash
   terraform plan
   # Should show no changes if infrastructure is deployed
   ```

### For Team Leads

When onboarding new members:

1. Grant 1Password vault access
2. Create Linode API token with appropriate permissions
3. Share Resilio Sync keys securely
4. Review their first PR before they apply changes

## Additional Resources

- [Backend Setup Guide](BACKEND_SETUP.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Linode Provider Documentation](https://registry.terraform.io/providers/linode/linode/latest/docs)
- [Resilio Sync Documentation](https://help.resilio.com/)

## Getting Help

If you encounter issues:

1. Check [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Run diagnostic scripts in `scripts/`
3. Check Terraform logs: `export TF_LOG=DEBUG`
4. Open an issue on GitHub with logs and error messages

## Contributing

See the main [README.md](../README.md) for contribution guidelines.

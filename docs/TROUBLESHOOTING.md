# Terraform Troubleshooting Guide

This guide helps resolve common Terraform issues in this project.

## Table of Contents
- [Provider Lock File Issues](#provider-lock-file-issues)
- [Provider Version Constraint Errors](#provider-version-constraint-errors)
- [Backend Configuration Issues](#backend-configuration-issues)
- [Module Dependency Issues](#module-dependency-issues)

---

## Provider Lock File Issues

### Error: Locked provider does not match configured version constraint

**Full Error Message:**
```
Error: Failed to query available provider packages

Could not retrieve the list of available versions for provider linode/linode:
locked provider registry.terraform.io/linode/linode 2.37.0 does not match
configured version constraint ~> 3.5; must use terraform init -upgrade to
allow selection of new versions
```

**Cause:**
The `.terraform.lock.hcl` file contains an older version of the Linode provider (2.37.0) that doesn't satisfy the new version constraint (~> 3.5) in `provider.tf`.

**Solution 1: Automated Fix (Recommended)**

Run the provided fix script:

```bash
# Standard upgrade
bash scripts/fix-provider-lock.sh

# OR for a clean start (removes .terraform directory)
bash scripts/fix-provider-lock.sh --clean
```

**Solution 2: Manual Fix**

```bash
# Option A: Upgrade providers
terraform init -upgrade

# Option B: Clean start (if Option A fails)
rm -rf .terraform .terraform.lock.hcl
terraform init
```

**Why This Happened:**
The project was recently updated to use Linode provider version 3.5.x (from 2.x) to access newer features and improvements. The lock file needs to be updated to reflect this change.

---

### Error: Provider registry does not have a provider named hashicorp/linode

**Full Error Message:**
```
Error: Failed to query available provider packages

Could not retrieve the list of available versions for provider hashicorp/linode:
provider registry registry.terraform.io does not have a provider named
registry.terraform.io/hashicorp/linode

Did you intend to use linode/linode? If so, you must specify that source
address in each module which requires that provider.
```

**Cause:**
This error can occur when:
1. The `.terraform` directory contains cached data for the wrong provider source
2. A module has an implicit provider dependency using the old namespace

**Solution:**

```bash
# Remove cached provider data and reinitialize
rm -rf .terraform .terraform.lock.hcl
terraform init

# OR use the automated fix script
bash scripts/fix-provider-lock.sh --clean
```

**Note:** This project uses the correct provider source `linode/linode` in all configurations. The error is typically caused by stale cache data.

---

## Provider Version Constraint Errors

### Error: Unsupported Terraform Core version

**Full Error Message:**
```
Error: Unsupported Terraform Core version

on provider.tf line 17, in terraform:
  17:   required_version = "~> 1.10"

This configuration does not support Terraform version 1.5.7.
```

**Cause:**
Your Terraform version is older than the required version.

**Solution:**

This has been fixed in the current version. The `required_version` is now set to `>= 1.5.0` in `provider.tf:49`.

If you still see this error:
```bash
# Check your Terraform version
terraform version

# Update provider.tf if needed
# Change: required_version = "~> 1.10"
# To:     required_version = ">= 1.5.0"
```

---

## Backend Configuration Issues

See [BACKEND_SETUP.md](./BACKEND_SETUP.md) for detailed backend configuration and troubleshooting.

### Quick Backend Troubleshooting

**Problem:** Authentication errors with Linode Object Storage backend

**Solution:**
```bash
# Ensure credentials are loaded from 1Password
source scripts/setup-backend-credentials.sh

# Verify credentials are set
echo "Access Key: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
```

**Problem:** Bucket access errors

**Solution:**
- Verify bucket name in `provider.tf` matches your Linode bucket
- Check endpoint URL matches your region
- Ensure bucket exists and credentials have proper permissions

---

## Module Dependency Issues

### Error: Module not found

**Cause:**
Module source paths may be incorrect or modules not initialized.

**Solution:**
```bash
# Reinitialize to download/update modules
terraform init -upgrade

# Verify module structure
tree modules/
```

**Expected module structure:**
```
modules/
├── dns/
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── firewall/
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── linode/
│   ├── cloud-init.tpl
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
└── volume/
    ├── main.tf
    ├── outputs.tf
    └── variables.tf
```

---

## General Troubleshooting Steps

### 1. Check Terraform Version
```bash
terraform version
```
**Required:** >= 1.5.0

### 2. Validate Configuration
```bash
terraform validate
```

### 3. Check Provider Configuration
```bash
# View required providers
grep -A 15 "required_providers" provider.tf

# Expected output should show:
# - linode: source = "linode/linode", version = "~> 3.5"
# - random: source = "hashicorp/random", version = ">= 3.7.1"
# - http: source = "hashicorp/http", version = ">= 3.4.0"
```

### 4. Inspect Current Providers
```bash
terraform providers
```

### 5. Clean Slate (Nuclear Option)
```bash
# Remove all Terraform state and cache
rm -rf .terraform .terraform.lock.hcl

# Reinitialize
terraform init

# Note: This is safe if you're using a remote backend
# Your state file is stored remotely and will be downloaded
```

---

## Common Provider Version Issues

### Linode Provider Versions

| Version | Release Date | Notable Changes |
|---------|--------------|-----------------|
| 2.37.0  | 2023        | Legacy version (old lock file) |
| 3.5.x   | 2024        | Current version (required) |

**Breaking Changes in 3.x:**
- Some resource attributes renamed
- New authentication methods
- Enhanced metadata support

**Migration Path:**
```bash
# Update lock file
terraform init -upgrade

# Review plan for any breaking changes
terraform plan

# Apply if everything looks good
terraform apply
```

---

## Getting More Help

### Debug Mode

Run Terraform with debug logging:
```bash
# Set log level
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log

# Run your command
terraform init -upgrade

# Review logs
cat terraform-debug.log
```

### Validate Provider Configuration

```bash
# Check provider versions that will be used
terraform version

# Show provider requirements
terraform providers schema -json | jq '.provider_schemas'
```

### Check Internet Connectivity

```bash
# Test access to Terraform Registry
curl -I https://registry.terraform.io/v1/providers/linode/linode/versions

# Test access to Linode API
curl -I https://api.linode.com/v4/regions
```

---

## Quick Reference

### Useful Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/fix-provider-lock.sh` | Fix provider lock file issues | `bash scripts/fix-provider-lock.sh` |
| `scripts/fix-provider-lock.sh --clean` | Clean initialization | `bash scripts/fix-provider-lock.sh --clean` |
| `scripts/setup-backend-credentials.sh` | Load backend credentials | `source scripts/setup-backend-credentials.sh` |

### Useful Commands

```bash
# Initialize and upgrade providers
terraform init -upgrade

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Show current state
terraform show

# List resources
terraform state list

# Check for drift
terraform plan -refresh-only
```

---

## Still Stuck?

1. Check the [Terraform documentation](https://www.terraform.io/docs)
2. Check the [Linode Provider documentation](https://registry.terraform.io/providers/linode/linode/latest/docs)
3. Review recent commits for configuration changes: `git log --oneline -10`
4. Check if there are any pending changes: `git status`

## Contributing

If you discover a new issue and solution, please add it to this troubleshooting guide!

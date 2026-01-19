# CLAUDE.md

This file provides guidance for Claude Code when working with this repository.

## Project Overview

This is a **Terraform infrastructure-as-code** project that deploys Resilio Sync across multiple Linode regions with comprehensive security, DNS management, and automated backups.

**Key technologies**: Terraform, Linode Cloud, Resilio Sync, Cloud-Init, Ubuntu

## Repository Structure

```
.
├── main.tf                 # Main orchestration - modules and firewall update logic
├── variables.tf            # Input variable definitions with validation
├── outputs.tf              # Output definitions
├── provider.tf             # Provider configuration (Linode)
├── data.tf                 # Data sources (IP detection)
├── tags.tf                 # Tag definitions
├── modules/
│   ├── linode/             # Resilio Sync instance module (cloud-init provisioning)
│   ├── volume/             # Block storage module with lifecycle protection
│   ├── dns/                # DNS record management module
│   ├── firewall/           # Legacy firewall module
│   ├── jumpbox/            # Bastion host module
│   ├── jumpbox-firewall/   # Jumpbox firewall rules
│   └── resilio-firewall/   # Resilio instance firewall rules
├── scripts/                # Helper scripts (backend setup, provider fixes, etc.)
├── docs/                   # Documentation (setup guides, troubleshooting)
└── .github/                # GitHub configurations (dependabot)
```

## Essential Commands

### Terraform Operations

```bash
# Initialize (download providers and modules)
terraform init

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show outputs
terraform output
```

### Pre-commit Validation

```bash
# Install pre-commit hooks
pre-commit install

# Run all checks manually
pre-commit run --all-files
```

### Provider Lock File Issues

```bash
# Fix provider lock file issues
bash scripts/fix-provider-lock.sh

# Full reset if needed
bash scripts/fix-provider-lock.sh --clean
```

## Code Patterns and Conventions

### Module Structure

Each module follows this pattern:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables with descriptions and validation
- `outputs.tf` - Output values
- `README.md` - Module documentation

### Sensitive Variables

Variables containing secrets are marked `sensitive = true`:
- `linode_token`
- `resilio_folder_keys`, `resilio_folder_key`
- `resilio_license_key`
- `ubuntu_advantage_token`
- `object_storage_access_key`, `object_storage_secret_key`

### Resource Naming

Resources use the pattern: `${var.project_name}-${region}` (e.g., `resilio-sync-us-east`)

### For_each vs Count

The project uses `for_each` with `toset(var.regions)` for multi-region deployment rather than count-based iteration.

## Validation and Testing

### Before Committing

1. Run `terraform fmt -recursive` to format all files
2. Run `terraform validate` to check syntax
3. Run `pre-commit run --all-files` for comprehensive checks

### Pre-commit Hooks Include

- `terraform_fmt` - Code formatting
- `terraform_validate` - Syntax validation
- `terraform_trivy` - Security scanning (MEDIUM, HIGH, CRITICAL)
- `detect-secrets` - Prevents credential commits
- `no-commit-to-branch` - Blocks commits to main/master

## CRITICAL: Destructive Changes Warning

### Instance Recreation Triggers

**WARNING**: The following variable changes will **DESTROY AND RECREATE** instances because they modify the `metadata.user_data` (cloud-init):

- `ssh_public_key`
- `resilio_folder_keys` or `resilio_folder_key`
- `resilio_license_key`
- `tld`
- `ubuntu_advantage_token`
- `object_storage_access_key`, `object_storage_secret_key`, `object_storage_endpoint`, `object_storage_bucket`

**Also triggers recreation**:
- `instance_type` changes (may recreate depending on Linode provider)
- `region` changes (always recreates)
- `project_name` changes (triggers new random_id)

### Data Loss Risk Assessment

**Protected (data survives instance recreation)**:
- Volumes have `prevent_destroy = true` in `modules/volume/main.tf:14`
- Volumes ignore label/region changes (`ignore_changes = [label, region]`)
- Resilio identity and license are stored on the volume and preserved (cloud-init checks before creating)

**AT RISK**:
- If ALL instances are recreated simultaneously, sync is interrupted until instances come back online
- Any data not yet synced to other regions or Object Storage backup will be lost
- The cloud-init `fs_setup` at `modules/linode/cloud-init.tpl:33` has `overwrite: true` which could format the volume partition on recreation

### Safe Deployment Procedures

**Before making changes that trigger instance recreation**:

1. **Verify backups are current**:
   ```bash
   ssh -J ac-user@jumpbox ac-user@resilio-instance
   sudo tail -20 /var/log/resilio-backup.log
   ```

2. **Check sync status** - Ensure all data is synced across regions before proceeding

3. **Apply changes one region at a time** using targeted applies:
   ```bash
   # Apply to us-east first
   terraform apply -target='module.linode_instances["us-east"]'

   # Wait for sync to complete, then apply to other regions
   terraform apply -target='module.linode_instances["eu-west"]'

   # Finally, apply remaining changes
   terraform apply
   ```

4. **Never apply during active sync operations** - Wait for sync to complete

### Safety Mechanisms Implemented

The following safety mechanisms are in place to prevent data loss:

1. **Lifecycle rules ignore metadata changes** (`modules/linode/main.tf`):
   - `ignore_changes = [metadata]` prevents instance recreation when cloud-init variables change
   - Configuration changes require manual intervention or explicit replacement

2. **fs_setup does not overwrite data volume** (`modules/linode/cloud-init.tpl:33`):
   - `overwrite: false` ensures existing data is never formatted on instance recreation

3. **Create before destroy** (`modules/linode/main.tf`):
   - `create_before_destroy = true` ensures new instance is created and can sync before old one is removed

### Forcing Instance Replacement

When you DO need to replace an instance (e.g., to apply new cloud-init config):

```bash
# Replace a specific instance explicitly
terraform apply -replace='module.linode_instances["us-east"].linode_instance.resilio'

# Wait for sync, then replace next region
terraform apply -replace='module.linode_instances["eu-west"].linode_instance.resilio'
```

### Resizing Volumes (Automatic Expansion)

Volume resizing is **non-destructive** and automatic. The filesystem expands on next boot.

**To increase volume size:**

1. Update `volume_size` in `terraform.tfvars`:
   ```hcl
   volume_size = 50  # Increase from current size
   ```

2. Apply the change:
   ```bash
   terraform apply
   ```

3. Reboot the instance (or wait for next reboot):
   ```bash
   ssh -J ac-user@<jumpbox> ac-user@<resilio-instance>
   sudo reboot
   ```

4. Verify expansion (after reboot):
   ```bash
   df -h /mnt/resilio-data
   cat /var/log/volume-expand.log
   ```

**How it works:**
- A systemd service (`volume-auto-expand.service`) runs on every boot
- It compares block device size vs partition size
- If volume was resized, it runs `growpart` and `resize2fs` automatically
- Expansion happens before Resilio Sync starts
- Logs are written to `/var/log/volume-expand.log`

**Manual expansion (if needed):**
```bash
sudo /usr/local/bin/volume-auto-expand.sh
```

**Note**: Linode volumes can only be **increased**, never decreased.

## Important Implementation Details

### Firewall Rules Update

The `terraform_data.update_resilio_firewall` resource in `main.tf:122` uses a local-exec provisioner to update firewall rules via Linode API after instances are created (avoids circular dependency).

### Volume Lifecycle Protection

Volumes have lifecycle protection enabled. See `docs/VOLUME_RESIZE_SAFETY.md` for safe expansion procedures.

### Cloud-Init Template

Instance provisioning uses cloud-init template at `modules/linode/cloud-init.tpl` for:
- User creation (`ac-user`)
- SSH key configuration
- Resilio Sync installation and configuration
- Volume mounting
- Backup script setup (when Object Storage is configured)

**Note**: The cloud-init runs on every instance creation. The template includes checks to preserve existing Resilio identity and license (lines 282-302), but other configurations will be reapplied.

### SSH Access Pattern

All SSH access goes through the jumpbox (bastion host):
```bash
ssh -J ac-user@<jumpbox-ip> ac-user@<resilio-instance-ip>
```

## Common Tasks

### Adding a New Variable

1. Add to `variables.tf` with description, type, validation (if needed)
2. Pass to relevant modules in `main.tf`
3. Update module's `variables.tf` to accept it
4. Add to `terraform.tfvars.example` with example value

### Adding a New Region

Simply add the region code to the `regions` variable - the for_each pattern handles the rest.

### Adding/Removing Resilio Folders (Non-Destructive)

Folder configuration is stored on the persistent volume at `/mnt/resilio-data/.sync/folders.json`. This allows folder changes **without recreating instances**.

**Via SSH (recommended for adding folders):**

```bash
# Connect to instance via jumpbox
ssh -J ac-user@<jumpbox-ip> ac-user@<resilio-instance-ip>

# List current folders
sudo resilio-folders list

# Add a new folder
sudo resilio-folders add "BXXXXXXXXX..." my-new-folder

# Apply changes and restart Resilio
sudo resilio-folders apply

# Remove a folder (keeps data on disk)
sudo resilio-folders remove my-folder
sudo resilio-folders apply
```

**Via Terraform (initial deployment only):**

Adding folders via `resilio_folder_keys` variable will only affect **new instances**. Existing instances use their volume-based config and won't be recreated (due to `ignore_changes = [metadata]`).

To update existing instances after changing `resilio_folder_keys`:
1. SSH to each instance and use `resilio-folders add`
2. OR force instance replacement one region at a time:
   ```bash
   terraform apply -replace='module.linode_instances["us-east"].linode_instance.resilio'
   # Wait for sync, then next region
   ```

### Modifying Firewall Rules

- Jumpbox firewall: `modules/jumpbox-firewall/main.tf`
- Resilio firewall: `modules/resilio-firewall/main.tf` (initial rules) and `main.tf:122` (dynamic update via API)

## Documentation References

- [Setup Guide](docs/SETUP.md) - First-time setup
- [Backend Setup](docs/BACKEND_SETUP.md) - Remote state configuration
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues
- [Firewall Setup](docs/FIREWALL_SETUP.md) - Firewall configuration
- [Volume Resize](docs/VOLUME_RESIZE_SAFETY.md) - Safe volume expansion
- [Object Storage](docs/OBJECT_STORAGE_SETUP.md) - Backup configuration

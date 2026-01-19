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

## Important Implementation Details

### Firewall Rules Update

The `terraform_data.update_resilio_firewall` resource in `main.tf:122` uses a local-exec provisioner to update firewall rules via Linode API after instances are created (avoids circular dependency).

### Volume Lifecycle Protection

Volumes have lifecycle protection enabled. See `docs/VOLUME_RESIZE_SAFETY.md` for safe expansion procedures.

### Cloud-Init Template

Instance provisioning uses cloud-init template at `modules/linode/user_data.tftpl` for:
- User creation (`ac-user`)
- SSH key configuration
- Resilio Sync installation and configuration
- Volume mounting
- Backup script setup (when Object Storage is configured)

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

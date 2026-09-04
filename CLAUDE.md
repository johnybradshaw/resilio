# CLAUDE.md

This file provides guidance for AI assistants (such as Claude) when working with this repository.

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
├── scripts/
│   ├── cloud-init/         # Scripts transferred to instances via file provisioner
│   └── *.sh                # Helper scripts (backend setup, provider fixes, etc.)
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
- `resilio_folders` (contains folder keys)
- `resilio_folder_keys`, `resilio_folder_key` (deprecated)
- `resilio_license_key`
- `ubuntu_advantage_token`
- `object_storage_access_key`, `object_storage_secret_key`
- `ssh_private_key` (for file provisioner)
- SSL certificate variables (auto-generated via ACME)

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

**IMPORTANT**: The following variable changes affect `metadata.user_data` (cloud-init) and would *normally* trigger instance recreation:

- `ssh_public_key`
- `resilio_folder_keys` or `resilio_folder_key`
- `resilio_license_key`
- `tld`
- `ubuntu_advantage_token`
- `object_storage_access_key`, `object_storage_secret_key`, `object_storage_endpoint`, `object_storage_bucket`

**These changes DO trigger recreation.** `metadata` is deliberately *not* in
`ignore_changes` (commit `94df96a`, "Enable instance recreation for cloud-init
changes"). The reasoning: silently absorbing cloud-init drift means a renewed SSL
certificate, a rotated Object Storage key or a hardening fix can sit in Terraform
state for months without ever reaching an instance. A visible replacement is the
lesser evil.

**The risk is therefore blast radius, not silence.** A plain `terraform apply` will
replace **all regions at once**, and because `create_before_destroy` is not used
(see below), every region is offline simultaneously and sync stops everywhere.
Always stage the rollout one region at a time - see 'Safe Deployment Procedures'.

**Variables that DO trigger recreation**:
- `instance_type` changes (may recreate depending on Linode provider)
- `region` changes (always recreates)
- `project_name` changes (triggers new random_id)

### Data Loss Risk Assessment

**Protected (data survives instance recreation)**:
- Volumes have `prevent_destroy = true` in `modules/volume/main.tf:30`
- Volumes ignore label/region changes (`ignore_changes = [label, region]`)
- Resilio identity and license are stored on the volume and preserved (cloud-init checks before creating)

**AT RISK**:
- If ALL instances are recreated simultaneously, sync is interrupted until instances come back online
- Any data not yet synced to other regions or Object Storage backup will be lost

### Safe Deployment Procedures

**Before making changes that trigger instance recreation**:

1. **Verify backups are current** - and that a real backup script is installed,
   not the cloud-init placeholder:
   ```bash
   ssh -J cloud-user@<jumpbox> cloud-user@<instance>
   ls -l /usr/local/bin/resilio-backup.sh   # placeholder ~250B, real script ~6.5KB
   sudo tail -20 /var/log/resilio-backup.log
   sudo cat /var/lib/resilio-backup/last-success
   ```
   `Backup script not yet provisioned` means the placeholder is installed and
   **no backup has ever run on this host**. The placeholder exits 0, so cron
   records success regardless.

2. **Check sync status** - Ensure all data is synced across regions before proceeding

3. **Apply changes one region at a time.** Never a bare `terraform apply` when
   cloud-init has changed - that replaces every region in `var.regions`
   together. Target **each** region explicitly; the list below must cover all of
   them, or the final unrestricted apply replaces whatever was missed, all at
   once.
   ```bash
   for r in us-east eu-west fr-par ap-northeast it-mil; do
     terraform apply -target="module.linode_instances[\"$r\"]"
     # then WAIT: boot, cloud-init completion, and re-sync, before the next
   done
   terraform apply     # reconciles firewall, DNS and anything non-instance
   ```

   > **`-target` leaves the firewall stale, and the region cannot sync until you
   > fix it.** `terraform_data.update_resilio_firewall` lives in the root module
   > and depends on the instance IPs, so a targeted apply **excludes** it. The
   > replaced instance comes back with a NEW IP that is absent from the shared
   > firewall's `resilio-all-tcp/udp/icmp` rules, and its peers drop its traffic.
   > The instance looks healthy in every API and console view while syncing with
   > nothing.
   >
   > Targeting the resource does not help: it pulls in every instance as a
   > dependency and would replace them all. Reconcile out of band after each
   > region, which is exactly what the provisioner does anyway:
   >
   > ```bash
   > # rewrite resilio-all-* with the CURRENT instance IPs
   > curl -sS -H "Authorization: Bearer $LINODE_TOKEN" \
   >   https://api.linode.com/v4/networking/firewalls/<resilio-fw-id>/rules
   > # ...substitute the new IP, then PUT the full ruleset back (PUT REPLACES it,
   > # so include inbound, inbound_policy, outbound and outbound_policy)
   > ```
   >
   > Verify before moving on:
   > ```bash
   > curl -sS -H "Authorization: Bearer $LINODE_TOKEN" \
   >   https://api.linode.com/v4/networking/firewalls/<id> | \
   >   python3 -c 'import json,sys;[print(r["addresses"]["ipv4"]) for r in json.load(sys.stdin)["rules"]["inbound"] if r["label"]=="resilio-all-tcp"]'
   > ```

   > **The jumpbox firewall goes stale the same way.** `allowed_ssh_cidr` is
   > derived from the operator's detected public IP, so when that changes nobody
   > can SSH to any instance until `module.jumpbox_firewall` is applied. Check it
   > before starting a rollout - you will need SSH to verify each region.
   Use `-replace=...` instead when the config has not changed but you want to
   rebuild an instance anyway.

4. **Never apply during active sync operations** - Wait for sync to complete

### Safety Mechanisms Implemented

The following safety mechanisms are in place to prevent data loss:

1. **Volume protection is the primary data safeguard** (`modules/volume/main.tf:30`):
   - `prevent_destroy = true` and `ignore_changes = [label, region]` mean a volume is
     never destroyed or recreated. Instance replacement detaches and reattaches it.
   - Note there is deliberately NO `ignore_changes = [metadata]` on the instance, so
     cloud-init changes are visible as a replacement rather than silently dropped.

2. **fs_setup does not overwrite data volumes** (`modules/linode/cloud-init.tpl:39`):
   - Per-folder data volumes use `overwrite: false`, so existing filesystems are
     never reformatted on instance recreation. `disk_setup` does the same at line 29.
   - The OS temp partitions (`/dev/sdb1-3`, lines 34-36) DO use `overwrite: true`.
     That is intentional - they hold `/tmp`, `/var/log` and `/var/tmp` only.

3. **Create before destroy is NOT used** (`modules/linode/main.tf`):
   - Linode requires unique instance labels, so a replacement cannot be created
     while the old instance still exists. `create_before_destroy` was deliberately
     removed for this reason.
   - **Consequence**: a replaced instance is destroyed FIRST, then recreated. That
     region is offline for the duration. Replace one region at a time so the other
     regions keep serving and can re-sync the replaced one.

### Forcing Instance Replacement

When you DO need to replace an instance (e.g., to apply new cloud-init config):

```bash
# Replace a specific instance explicitly
terraform apply -replace='module.linode_instances["us-east"].linode_instance.resilio'

# Wait for sync, then replace next region
terraform apply -replace='module.linode_instances["eu-west"].linode_instance.resilio'
```

### Per-Folder Volumes Architecture

Each Resilio folder gets its own dedicated Linode volume, enabling:
- **Independent sizing**: Allocate storage based on each folder's needs
- **Isolation**: Folder data on separate block devices
- **Safe operations**: Volumes protected with `prevent_destroy = true`

**Device Mapping:**
```
/dev/sda  → Boot disk
/dev/sdb  → Temp disk (tmp, var/log, var/tmp)
/dev/sdc  → First folder volume (alphabetically sorted)
/dev/sdd  → Second folder volume
...       → Up to 13 folders (sdc-sdo)
```

**Volume/Mount Naming:**
- Linode volume label: `rs-{folder_name}-{region_prefix}` (e.g., `rs-documents-us-eas`, max 32 chars)
- Filesystem label: `rs-{folder_name}` truncated to 16 chars (ext4 limit)
- Mount point: `/mnt/resilio-data/{folder_name}`

**Important:** ext4 filesystem labels are limited to 16 characters. The cloud-init includes a fixup script that relabels filesystems on boot if they don't match the expected label.

**Configuration in terraform.tfvars:**
```hcl
resilio_folders = {
  documents = { key = "BXXXXXXX...", size = 50 }
  photos    = { key = "BYYYYYYY...", size = 200 }
  backups   = { key = "BZZZZZZ...", size = 500 }
}
```

**Validation rules:**
- Folder names: 2-32 characters, lowercase alphanumeric with hyphens
- Volume size: 10-10000 GB
- Key length: minimum 20 characters
- Maximum 13 folders per instance (device letter limit)

### Resizing Volumes (Automatic Expansion)

Volume resizing is **non-destructive** and automatic. The filesystem expands on next boot.

**To increase a folder's volume size:**

1. Update the folder's size in `terraform.tfvars`:
   ```hcl
   resilio_folders = {
     documents = { key = "BXXXXXXX...", size = 100 }  # Increased from 50
     photos    = { key = "BYYYYYYY...", size = 200 }
   }
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
   # Check all folder volumes
   sudo resilio-folders status

   # Or check specific mount
   df -h /mnt/resilio-data/documents

   # View expansion logs
   cat /var/log/volume-expand.log
   ```

**How it works:**
- A systemd service (`volume-auto-expand.service`) runs on every boot
- It iterates over all per-folder volumes from `/etc/resilio-sync/folder-device-map.json`
- For each volume, it compares block device size vs partition size
- If volume was resized, it runs `growpart` and `resize2fs` automatically
- **Dual verification**: Checks both filesystem label AND mount point before expanding
- Expansion happens before Resilio Sync starts
- Logs are written to `/var/log/volume-expand.log`

**Manual expansion (if needed):**
```bash
sudo /usr/local/bin/volume-auto-expand.sh
```

**Note**: Linode volumes can only be **increased**, never decreased.

## Important Implementation Details

### Firewall Rules Update

The `terraform_data.update_resilio_firewall` resource in `main.tf` uses a local-exec provisioner to update firewall rules via Linode API after instances are created (avoids circular dependency).

### Volume Lifecycle Protection

Volumes have lifecycle protection enabled. See `docs/VOLUME_RESIZE_SAFETY.md` for safe expansion procedures.

### Cloud-Init Template and Script Provisioning

Instance provisioning uses a two-phase approach to stay within Linode's 16KB user_data limit:

**Phase 1: Cloud-Init** (`modules/linode/cloud-init.tpl`)
- User creation (`ac-user`)
- SSH key configuration
- Package installation
- Volume mounting and filesystem setup
- Resilio Sync installation and basic configuration
- Minimal placeholder scripts for bootstrap

**Phase 2: Script Provisioner** (`null_resource.provision_scripts`)
- Transfers full-featured scripts via SSH after instance boot
- Uses Terraform's `file` provisioner through the jumpbox
- Scripts are stored in `scripts/cloud-init/` as templates

**Scripts in `scripts/cloud-init/`:**
| Script | Purpose |
|--------|---------|
| `resilio-folders.sh.tpl` | Folder management CLI (list, add, remove, status) |
| `volume-auto-expand.sh.tpl` | Automatic filesystem expansion on volume resize |
| `resilio-backup.sh.tpl` | Backup to Object Storage with versioning |
| `resilio-rehydrate.sh.tpl` | Restore from backup to new/rebuilt VMs |
| `resilio-backup-watch.sh.tpl` | Realtime backup via inotify (for hybrid mode) |
| `collect-diagnostics.sh` | Collect logs for troubleshooting |

**To enable script provisioning**, set these variables:
```hcl
provision_scripts = true
ssh_private_key   = file("~/.ssh/id_rsa")
jumpbox_ip        = module.jumpbox.ip_address
```

**Note**: Without `provision_scripts = true`, instances use minimal placeholder scripts from cloud-init. The full scripts can be manually transferred or will be installed on the next `terraform apply` with provisioning enabled.

### SSL Certificates (Let's Encrypt)

The infrastructure automatically provisions SSL certificates via Let's Encrypt using DNS-01 challenge:

- **ACME Provider**: Uses `vancluever/acme` Terraform provider
- **DNS Challenge**: Validates via Linode DNS (requires domain to use Linode nameservers)
- **Certificate Scope**: Wildcard cert for `*.{project_name}.{tld}` plus per-region SANs
- **Auto-Renewal**: Certificates renew when < 30 days remaining

**Certificate files on instances:**
- `/etc/resilio-sync/ssl/cert.pem` - Server certificate
- `/etc/resilio-sync/ssl/privkey.pem` - Private key (mode 0640)
- `/etc/resilio-sync/ssl/chain.pem` - CA chain

**Resilio Web UI**: Accessible via HTTPS on port 8888 with valid SSL certificate.

### Backup Configuration

Since Resilio syncs data across all regions, only ONE region needs to run backups to Object Storage. This is controlled by the `backup_regions` variable:

```hcl
# In terraform.tfvars
backup_regions = ["us-east"]  # Only us-east runs backups
```

- Empty list `[]` disables backups on all regions
- Set to one region to avoid redundant storage costs
- Backups run daily at 2 AM via cron

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

### Adding/Removing Resilio Folders

With per-folder volumes, each folder requires its own dedicated volume. Folder configuration is stored at `/mnt/resilio-data/.sync/folders.json`.

**Via Terraform (recommended for adding folders):**

With per-folder volumes, you should add new folders via Terraform to create their volumes:

1. Add the folder to `terraform.tfvars`:
   ```hcl
   resilio_folders = {
     documents = { key = "BXXXXXXX...", size = 50 }
     photos    = { key = "BYYYYYYY...", size = 200 }
     new-folder = { key = "BZZZZZZZ...", size = 100 }  # New folder
   }
   ```

2. Apply the change (creates volume only, no instance recreation):
   ```bash
   terraform apply
   ```

3. Force instance replacement to attach the new volume:
   ```bash
   # Replace one region at a time
   terraform apply -replace='module.linode_instances["us-east"].linode_instance.resilio'
   # Wait for sync, then next region
   terraform apply -replace='module.linode_instances["eu-west"].linode_instance.resilio'
   ```

**Via SSH (for config changes on existing volumes):**

```bash
# Connect to instance via jumpbox
ssh -J ac-user@<jumpbox-ip> ac-user@<resilio-instance-ip>

# List current folders and volumes
sudo resilio-folders list

# Check volume disk usage
sudo resilio-folders status

# Add a folder to Resilio config (volume must already exist)
sudo resilio-folders add "BXXXXXXXXX..." folder-name

# Apply changes and restart Resilio
sudo resilio-folders apply

# Remove a folder from config (keeps data on disk)
sudo resilio-folders remove folder-name
sudo resilio-folders apply
```

**Note:** Removing a folder from Terraform will NOT delete the volume (protected by `prevent_destroy = true`). To fully remove:
1. Remove from `terraform.tfvars`
2. Manually delete the volume via Linode console or API

### Modifying Firewall Rules

- Jumpbox firewall: `modules/jumpbox-firewall/main.tf`
- Resilio firewall: `modules/resilio-firewall/main.tf` (initial rules) and `terraform_data.update_resilio_firewall` in `main.tf` (dynamic update via API)

## Documentation References

- [Setup Guide](docs/SETUP.md) - First-time setup
- [Backend Setup](docs/BACKEND_SETUP.md) - Remote state configuration
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues
- [Firewall Setup](docs/FIREWALL_SETUP.md) - Firewall configuration
- [Volume Resize](docs/VOLUME_RESIZE_SAFETY.md) - Safe volume expansion
- [Object Storage](docs/OBJECT_STORAGE_SETUP.md) - Backup configuration

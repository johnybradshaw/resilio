# Resilio Sync Multi-Region Infrastructure

A production-ready Terraform solution for deploying Resilio Sync on Linode across multiple regions, with comprehensive security, DNS management, and automated backups.

## ✨ Features

- **Multi-Region Deployment**: Deploy across multiple Linode regions with automatic cross-region synchronization
- **Multiple Folder Support**: Sync multiple Resilio folders simultaneously with dedicated directories per folder key
- **Automated Backups**: Daily incremental backups to Linode Object Storage with 30-day retention
- **Dedicated Logging**: Resilio Sync logs to `/var/log/resilio-sync/sync.log` with 7-day retention
- **Secure by Default**: Firewall-protected instances with configurable SSH access control via jumpbox (bastion)
- **Automated DNS Management**: Automatic A and AAAA record creation with Linode DNS
- **Block Storage**: Persistent volumes with encryption support and comprehensive lifecycle protection
- **Volume Resize Safety**: Online volume expansion with zero downtime and data loss protection
- **Cloud-Init Bootstrap**: Automated instance configuration with Ubuntu Pro hardening
- **State Management**: Configurable remote state backend support (S3, Terraform Cloud, GCS, Azure)
- **CI/CD Ready**: Pre-commit hooks for automated validation and security scanning

## 📋 Prerequisites

- **Terraform** >= 1.5.0
- **Linode API Token** with full permissions
- **SSH Public Key** for instance access
- **Resilio Sync** folder key and license key
- **Domain Name** for DNS management
- (Optional) **Ubuntu Advantage** token for Ubuntu Pro features
- (Optional) **1Password CLI** for secure backend credential management

## 🚀 Quick Start

> **First time setting up?** See the detailed [Setup Guide](docs/SETUP.md) for comprehensive instructions.

### 1. Clone and Configure

```bash
git clone https://github.com/johnybradshaw/resilio.git
cd resilio
```

### 2. Set Up Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

**Required variables:**
```hcl
linode_token           = "your-linode-api-token"
ssh_public_key         = "ssh-rsa AAAA..."
resilio_folder_keys    = ["your-resilio-folder-key-1", "your-resilio-folder-key-2"]  # Support multiple folders
resilio_license_key    = "your-resilio-license"
tld                    = "example.com"
ubuntu_advantage_token = "your-ubuntu-pro-token"  # Optional but recommended
```

**Optional backup configuration:**
```hcl
# Enable automated backups to Linode Object Storage
# See docs/OBJECT_STORAGE_SETUP.md for setup instructions
object_storage_access_key = "your-access-key"       # Get from Linode Object Storage
object_storage_secret_key = "your-secret-key"
object_storage_bucket     = "resilio-backups"       # Must create bucket first
object_storage_endpoint   = "us-east-1.linodeobjects.com"
```

**Security feature:**
```hcl
# Your IP is auto-detected by default for maximum security!
# Leave allowed_ssh_cidr unset to use auto-detection
# Or set explicitly if needed:
# allowed_ssh_cidr = "YOUR_IP/32"
```

### 3. (Optional) Configure Remote State Backend

**Option 1: Linode Object Storage (Recommended)**

See [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md) for detailed instructions on setting up Linode Object Storage backend with 1Password encryption.

Quick setup:
```bash
# Set up credentials in 1Password
# Uncomment backend block in provider.tf
# Load credentials and initialize
source scripts/setup-backend-credentials.sh
terraform init
```

**Option 2: Other Backends**

```bash
cp backend.tf.example backend.tf
# Edit backend.tf and uncomment your preferred backend
# Options: Terraform Cloud, GCS, Azure Blob Storage
```

### 4. Initialize and Deploy

```bash
# Download providers and modules
terraform init

# Review what will be created
terraform plan

# Deploy infrastructure
terraform apply
```

### 5. Configure DNS

After deployment, update your domain registrar with Linode's nameservers:

```bash
terraform output dns_nameservers
```

Configure these at your registrar:
- ns1.linode.com
- ns2.linode.com
- ns3.linode.com
- ns4.linode.com
- ns5.linode.com

## 📁 Repository Structure

```
.
├── main.tf                      # Main configuration
├── variables.tf                 # Input variables with validation
├── outputs.tf                   # Output definitions
├── provider.tf                  # Provider configuration
├── tags.tf                      # Tag definitions
├── backend.tf.example           # Remote state backend examples
├── terraform.tfvars.example     # Example variables file
├── .pre-commit-config.yaml      # Pre-commit hooks
├── .tflint.hcl                  # TFLint configuration
├── .gitignore                   # Git ignore rules
├── modules/
│   ├── linode/                  # Linode instance module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── README.md
│   │   └── cloud-init.tpl
│   ├── volume/                  # Block storage module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── firewall/                # Firewall module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── dns/                     # DNS management module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
└── LICENSE
```

## 📊 Input Variables

### Required Variables

| Name | Description | Type | Sensitive |
|------|-------------|------|-----------|
| `linode_token` | Linode API token | `string` | Yes |
| `ssh_public_key` | SSH public key for instance access | `string` | No |
| `resilio_folder_keys` | List of Resilio Sync folder keys (supports multiple folders) | `list(string)` | Yes |
| `resilio_license_key` | Resilio Sync license key | `string` | Yes |
| `tld` | Top-Level Domain (e.g., "example.com") | `string` | No |
| `ubuntu_advantage_token` | Ubuntu Advantage token | `string` | Yes |

### Optional Variables

| Name | Description | Type | Default | Validation |
|------|-------------|------|---------|------------|
| `regions` | Linode regions to deploy | `list(string)` | `["us-east", "eu-west"]` | Min: 1 region |
| `instance_type` | Linode instance type | `string` | `"g6-standard-1"` | - |
| `volume_size` | Storage volume size (GB) | `number` | `20` | 10-10000 GB |
| `project_name` | Resource name prefix | `string` | `"resilio-sync"` | - |
| `allowed_ssh_cidr` | CIDR for SSH access to jumpbox | `string` | Auto-detected current IP | Valid CIDR |
| `jumpbox_region` | Jumpbox region | `string` | `"us-east"` | - |
| `jumpbox_instance_type` | Jumpbox instance type | `string` | `"g6-nanode-1"` | - |
| `cloud_user` | Non-root user for SSH access | `string` | `"ac-user"` | - |
| `tags` | Resource tags | `list(string)` | `["deployment: terraform", "app: resilio"]` | - |

### Backup Variables (Optional)

| Name | Description | Type | Default | Sensitive |
|------|-------------|------|---------|-----------|
| `object_storage_access_key` | Object Storage access key | `string` | `"CHANGEME"` | Yes |
| `object_storage_secret_key` | Object Storage secret key | `string` | `"CHANGEME"` | Yes |
| `object_storage_endpoint` | Object Storage endpoint | `string` | `"us-east-1.linodeobjects.com"` | No |
| `object_storage_bucket` | Object Storage bucket name | `string` | `"resilio-backups"` | No |

## 📤 Outputs

### Instance Information

| Output | Description |
|--------|-------------|
| `instance_ips` | Map of region → `{ ipv4, ipv6, fqdn }` |
| `instance_ids` | Map of region → instance ID |
| `jumpbox_ip` | Jumpbox (bastion) IP address |
| `jumpbox_ssh` | SSH command to connect to jumpbox |
| `ssh_connection_strings` | SSH commands to resilio instances via jumpbox (uses SSH jump host) |
| `allowed_ssh_cidr` | CIDR block used for SSH access (shows auto-detected IP) |

### Infrastructure Resources

| Output | Description |
|--------|-------------|
| `volume_ids` | Map of region → volume ID |
| `firewall_id` | Firewall ID protecting instances |
| `domain_id` | Linode DNS domain ID |
| `dns_nameservers` | Nameservers to configure at registrar |

## 🔐 Security Features

### Firewall Rules

- **Inbound Policy**: DROP (default deny)
- **Jumpbox Access**: Dedicated bastion host accessible via `allowed_ssh_cidr`
- **SSH Access**: External → Jumpbox → Resilio instances (SSH jump host pattern)
- **Inter-Instance**: Full mesh connectivity between resilio instances
- **ICMP**: Allowed from `allowed_ssh_cidr`
- **Outbound**: ACCEPT (all allowed)

### Hardening

- **Jumpbox (Bastion Host)**: Secure entry point with minimal attack surface
- Ubuntu Pro with security patches (when token provided)
- Automatic backups enabled
- Volume lifecycle protection
- Sensitive outputs properly marked
- Cloud-init based provisioning
- Root SSH disabled, SSH key authentication only (ac-user)

## 🛠️ Development Workflow

### Pre-commit Hooks

Install pre-commit hooks for automated validation:

```bash
# Install pre-commit (using pipx for isolated Python tools)
pipx install pre-commit
pipx install detect-secrets

# On a Mac
brew install trivy

# Install hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

**Included hooks:**
- `terraform fmt` - Format Terraform files
- `terraform validate` - Validate syntax
- `terraform trivy` - Security scanning (replaces deprecated tfsec)
- `detect-secrets` - Prevent credential commits

### Remote State Backend

Choose and configure a backend from `backend.tf.example`:

**Terraform Cloud (Recommended for teams):**
```hcl
terraform {
  backend "remote" {
    organization = "my-org"
    workspaces {
      name = "resilio-sync"
    }
  }
}
```

**AWS S3 with DynamoDB locking:**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "resilio/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

After configuring, migrate state:
```bash
terraform init -migrate-state
```

## 📝 Common Operations

### SSH into Instances

All SSH access goes through the jumpbox (bastion host) for security:

```bash
# 1. First, connect to the jumpbox
terraform output jumpbox_ssh

# 2. Get SSH commands to connect from jumpbox to resilio instances
terraform output ssh_connection_strings

# 3. Or connect directly using SSH jump host (-J flag)
# This connects to resilio via jumpbox in one command
ssh -J ac-user@$(terraform output -raw jumpbox_ip) ac-user@$(terraform output -json instance_ips | jq -r '.["us-east"].ipv4')
```

**SSH Jump Host Pattern**: The `-J` flag creates an SSH connection through the jumpbox, providing secure access without exposing resilio instances directly to the internet.

### Add/Remove Regions

Edit `terraform.tfvars`:
```hcl
regions = ["us-east", "eu-west", "ap-south"]
```

Then apply:
```bash
terraform apply
```

### Scale Instance Type

Edit `terraform.tfvars`:
```hcl
instance_type = "g6-standard-4"
```

Apply changes:
```bash
terraform apply
```

### Expand Volume Size

See [docs/VOLUME_RESIZE_SAFETY.md](docs/VOLUME_RESIZE_SAFETY.md) for detailed instructions.

Quick steps:
```bash
# 1. Edit terraform.tfvars - ONLY INCREASE SIZE (never decrease)
volume_size = 50  # Increase from 20 to 50 GB

# 2. Apply changes (online, no downtime)
terraform apply

# 3. SSH into each instance and resize filesystem
ssh -J ac-user@jumpbox.example.com ac-user@resilio-instance.example.com
sudo resize2fs /dev/disk/by-label/resilio

# 4. Verify new size
df -h /mnt/resilio-data
```

### View Resilio Logs

```bash
# SSH into instance
ssh -J ac-user@jumpbox.example.com ac-user@resilio-instance.example.com

# View Resilio Sync logs
sudo tail -f /var/log/resilio-sync/sync.log

# View systemd logs
sudo journalctl -u resilio-sync -f
```

### Manage Backups

See [docs/OBJECT_STORAGE_SETUP.md](docs/OBJECT_STORAGE_SETUP.md) for complete guide.

```bash
# View backup logs
sudo tail -f /var/log/resilio-backup.log

# Trigger manual backup
sudo /usr/local/bin/resilio-backup.sh

# List backups (from local machine with rclone configured)
rclone ls r:resilio-backups/

# Restore from backup
rclone sync r:resilio-backups/<hostname>/ /mnt/resilio-data/ --progress
```

## 🔄 Upgrade Guide

### Migrating DNS Records (v2.x to v3.x)

If upgrading from count-based DNS records to for_each:

```bash
# List current DNS records
terraform state list | grep domain_record

# Move each record (example)
terraform state mv \
  'module.dns.linode_domain_record.resilio_A[0]' \
  'module.dns.linode_domain_record.resilio_A["resilio-sync.us-east"]'
```

Or allow Terraform to recreate them (brief DNS interruption).

## 🐛 Troubleshooting

For detailed troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

### Init Fails with Provider Version

**Quick Fix:**
```bash
# Automated fix
bash scripts/fix-provider-lock.sh

# OR manually
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
```

**Common Errors:**
- `locked provider does not match configured version constraint` → Run `bash scripts/fix-provider-lock.sh`
- `Unsupported Terraform Core version` → Upgrade Terraform to >= 1.5.0
- `provider registry does not have a provider named hashicorp/linode` → Run `bash scripts/fix-provider-lock.sh --clean`

### DNS Not Resolving

1. Check nameservers are configured at registrar
2. Verify DNS records created: `terraform output dns_records`
3. Test DNS: `dig @ns1.linode.com your-domain.com`

### SSH Connection Refused

1. Check firewall allows your IP: Review `allowed_ssh_cidr`
2. Verify instance is running: `linode-cli linodes list`
3. Check cloud-init completed: Review Linode console

### Backend/State Issues

See [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md) for backend-specific troubleshooting.

## 📚 Documentation

### Module Documentation

Each module has detailed documentation:

- [Linode Instance Module](modules/linode/README.md)
- [Volume Module](modules/volume/README.md)
- [Firewall Module](modules/firewall/README.md)
- [DNS Module](modules/dns/README.md)

### Additional Documentation

- [Setup Guide](docs/SETUP.md) - Complete first-time setup and configuration guide
- [Backend Setup Guide](docs/BACKEND_SETUP.md) - Configure Linode Object Storage backend with 1Password
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Resolve common issues and errors
- [Firewall Setup Guide](docs/FIREWALL_SETUP.md) - Understanding and managing firewall configurations
- [Volume Resize Safety Guide](docs/VOLUME_RESIZE_SAFETY.md) - Safe volume expansion without downtime or data loss
- [Object Storage Setup Guide](docs/OBJECT_STORAGE_SETUP.md) - Configure automated backups to Linode Object Storage

### Helper Scripts

- `scripts/setup-backend-credentials.sh` - Load backend credentials from 1Password
- `scripts/fix-provider-lock.sh` - Fix provider lock file issues (use --clean flag for full reset)
- `scripts/import-existing-resources.sh` - Import existing Linode resources into Terraform state

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Install pre-commit hooks: `pre-commit install`
4. Make your changes
5. Run validation: `pre-commit run --all-files`
6. Submit a pull request

## 📄 License

This project is licensed under the [GPL-3.0](LICENSE) license.

## 🙏 Acknowledgments

- Built with [Terraform](https://www.terraform.io/)
- Powered by [Linode](https://www.linode.com/)
- Synced with [Resilio Sync](https://www.resilio.com/)

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/johnybradshaw/resilio/issues)
- **Linode Support**: [Linode Support](https://www.linode.com/support/)
- **Terraform Docs**: [Terraform Documentation](https://www.terraform.io/docs)

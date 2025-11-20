# Resilio Sync Multi-Region Infrastructure

A production-ready Terraform solution for deploying Resilio Sync on Linode across multiple regions, with comprehensive security, DNS management, and automated backups.

## ✨ Features

- **Secure Jumphost Architecture**: Hardened bastion host with fail2ban and minimal attack surface
- **Zero-Trust Network Access**: Resilio VMs only accessible via jumphost - no direct SSH access
- **Multi-Region Deployment**: Deploy across multiple Linode regions with automatic cross-region synchronization
- **Defense in Depth**: Multi-layer firewall rules with default-deny policies
- **Automated DNS Management**: Automatic A and AAAA record creation with Linode DNS
- **Block Storage**: Persistent volumes with encryption support and lifecycle protection
- **Cloud-Init Bootstrap**: Automated instance configuration with Ubuntu Pro hardening
- **State Management**: Configurable remote state backend support (S3, Terraform Cloud, GCS, Azure)
- **CI/CD Ready**: Pre-commit hooks for automated validation and security scanning

## 📋 Prerequisites

- **Terraform** ~> 1.10 (minimum 1.0.0)
- **Linode API Token** with full permissions
- **SSH Public Key** for instance access
- **Resilio Sync** folder key and license key
- **Domain Name** for DNS management
- (Optional) **Ubuntu Advantage** token for Ubuntu Pro features

## 🚀 Quick Start

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
resilio_folder_key     = "your-resilio-folder-key"
resilio_license_key    = "your-resilio-license"
tld                    = "example.com"
ubuntu_advantage_token = "your-ubuntu-pro-token"  # Optional but recommended
```

**Security configuration:**
```hcl
# Enable secure jumphost (HIGHLY RECOMMENDED)
enable_jumphost = true

# Restrict jumphost access to your IP only
allowed_ssh_cidr = "YOUR_IP/32"  # Default: "0.0.0.0/0" allows all

# Non-root admin username (for SSH with passwordless sudo)
admin_username = "admin"  # Default: "admin"
```

**Architecture:** When jumphost is enabled, Resilio VMs are completely isolated - only the jumphost can SSH to them. You SSH to the jumphost, then from there to Resilio VMs. All instances use non-root admin user with passwordless sudo for better security.

### 3. (Optional) Configure Remote State Backend

```bash
cp backend.tf.example backend.tf
# Edit backend.tf and uncomment your preferred backend
# Options: S3, Terraform Cloud, GCS, Azure Blob Storage
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
│   ├── jumphost/                # Secure jumphost/bastion module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── README.md
│   │   └── jumphost-init.tpl
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
| `resilio_folder_key` | Resilio Sync folder key | `string` | Yes |
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
| `admin_username` | Non-root admin user with sudo | `string` | `"admin"` | Lowercase, not 'root' |
| `allowed_ssh_cidr` | CIDR for SSH access | `string` | `"0.0.0.0/0"` | Valid CIDR |
| `enable_jumphost` | Enable secure jumphost | `bool` | `true` | - |
| `jumphost_region` | Jumphost region | `string` | `""` (first region) | - |
| `tags` | Resource tags | `list(string)` | `["deployment: terraform", "app: resilio"]` | - |

## 📤 Outputs

### Instance Information

| Output | Description |
|--------|-------------|
| `instance_ips` | Map of region → `{ ipv4, ipv6, fqdn }` |
| `instance_ids` | Map of region → instance ID |
| `ssh_connection_strings` | Ready-to-use SSH commands with admin user |
| `root_passwords` | Root passwords for emergency console access (SSH root login disabled) |

### Infrastructure Resources

| Output | Description |
|--------|-------------|
| `volume_ids` | Map of region → volume ID |
| `firewall_id` | Firewall ID protecting instances |
| `domain_id` | Linode DNS domain ID |
| `dns_nameservers` | Nameservers to configure at registrar |

## 🔐 Security Architecture

### Jumphost-Based Access (Default)

This infrastructure implements a **defense-in-depth** security model using a hardened jumphost (bastion):

```
Internet → Your IP → Jumphost → Resilio VMs
                      ↓
                 fail2ban
                 firewall
                 hardened
```

**Key Security Features:**
- **Zero Direct Access**: Resilio VMs have NO direct SSH access from internet
- **Single Entry Point**: Only jumphost accepts external SSH (from your IP only)
- **Hardened Bastion**: Minimal jumphost with fail2ban, auto-updates, SSH hardening
- **Defense in Depth**: Multiple firewall layers protecting infrastructure

### Jumphost Security Hardening

The jumphost is intentionally minimal and locked down:
- **Non-Root Access**: SSH root login disabled, admin user with passwordless sudo
- **Fail2ban**: Auto-bans after 3 failed SSH attempts (1 hour)
- **SSH Hardening**: Key-only auth, no passwords, rate limiting
- **Auto-Updates**: Unattended security patches
- **Minimal Software**: Only SSH and security tools installed
- **Instance Size**: Smallest Linode (g6-nanode-1) for minimal attack surface
- **Logging**: All access attempts logged
- **Connection Banner**: Warning banner on login

### Resilio VM Firewall Rules

**Inbound Policy**: DROP (default deny)
- **SSH Access**: Only from jumphost IP (when enabled)
- **Inter-VM**: Full TCP/UDP/ICMP mesh between Resilio instances
- **External**: All other inbound traffic BLOCKED
- **Outbound**: ACCEPT (all allowed)

### Additional Hardening

- Non-root admin user with passwordless sudo on all instances
- SSH root login disabled (root password only for emergency console access)
- Ubuntu Pro with CVE patches (when token provided)
- Automatic backups enabled on all instances
- Volume lifecycle protection (prevent accidental deletion)
- Sensitive outputs properly marked
- Cloud-init based provisioning
- SSH key authentication only (no passwords)

## 🛠️ Development Workflow

### Pre-commit Hooks

Install pre-commit hooks for automated validation:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

**Included hooks:**
- `terraform fmt` - Format Terraform files
- `terraform validate` - Validate syntax
- `terraform docs` - Generate documentation
- `tflint` - Lint Terraform code
- `tfsec` - Security scanning
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

### View Sensitive Outputs

```bash
# View root passwords
terraform output -json root_passwords

# View specific region password
terraform output -json root_passwords | jq '.["us-east"]'
```

### SSH into Instance

```bash
# Get connection strings (includes ProxyJump config when jumphost enabled)
terraform output ssh_connection_strings

# With jumphost (recommended):
# ssh -J admin@<jumphost-ip> admin@<resilio-vm-ip>

# Without jumphost (direct access):
# ssh admin@<resilio-vm-ip>

# Use sudo for privileged commands:
# ssh admin@<instance-ip> 'sudo systemctl status resilio-sync'
```

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

### Disable Jumphost (Not Recommended for Production)

If you need direct SSH access (e.g., development):

```hcl
enable_jumphost = false
```

**Warning**: This exposes Resilio VMs directly to the internet. Only use for non-production environments.

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

### Init Fails with Provider Version

```bash
# Clear provider cache
rm -rf .terraform .terraform.lock.hcl

# Re-initialize
terraform init -upgrade
```

### DNS Not Resolving

1. Check nameservers are configured at registrar
2. Verify DNS records created: `terraform output dns_records`
3. Test DNS: `dig @ns1.linode.com your-domain.com`

### SSH Connection Refused

1. Check firewall allows your IP: Review `allowed_ssh_cidr`
2. Verify instance is running: `linode-cli linodes list`
3. Check cloud-init completed: Review Linode console

## 📚 Module Documentation

Each module has detailed documentation:

- [Linode Instance Module](modules/linode/README.md)
- [Jumphost Module](modules/jumphost/README.md)
- [Volume Module](modules/volume/README.md)
- [Firewall Module](modules/firewall/README.md)
- [DNS Module](modules/dns/README.md)

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

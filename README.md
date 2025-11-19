# Resilio Sync Multi-Region Infrastructure

A production-ready Terraform solution for deploying Resilio Sync on Linode across multiple regions, with comprehensive security, DNS management, and automated backups.

## ✨ Features

- **Multi-Region Deployment**: Deploy across multiple Linode regions with automatic cross-region synchronization
- **Secure by Default**: Firewall-protected instances with configurable SSH access control
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

**Security tip:**
```hcl
# Set this to your IP for better security!
allowed_ssh_cidr = "YOUR_IP/32"  # Default: "0.0.0.0/0" allows all
```

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
| `allowed_ssh_cidr` | CIDR for SSH access | `string` | `"0.0.0.0/0"` | Valid CIDR |
| `tags` | Resource tags | `list(string)` | `["deployment: terraform", "app: resilio"]` | - |

## 📤 Outputs

### Instance Information

| Output | Description |
|--------|-------------|
| `instance_ips` | Map of region → `{ ipv4, ipv6, fqdn }` |
| `instance_ids` | Map of region → instance ID |
| `ssh_connection_strings` | Ready-to-use SSH commands |
| `root_passwords` | Root passwords (sensitive, use `terraform output -raw root_passwords`) |

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
- **SSH Access**: Restricted to `allowed_ssh_cidr` (ports 22, 2022)
- **Inter-Instance**: Full mesh connectivity between instances
- **ICMP**: Allowed from `allowed_ssh_cidr`
- **Outbound**: ACCEPT (all allowed)

### Hardening

- Ubuntu Pro with security patches (when token provided)
- Automatic backups enabled
- Volume lifecycle protection
- Sensitive outputs properly marked
- Cloud-init based provisioning

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
# Get connection string
terraform output ssh_connection_strings

# Or connect directly
ssh root@$(terraform output -json instance_ips | jq -r '.["us-east"].ipv4')
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

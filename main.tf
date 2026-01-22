# File structure:
# ├── main.tf           # Main configuration file
# ├── variables.tf      # Variable definitions
# ├── outputs.tf        # Output definitions
# ├── provider.tf       # Provider configuration
# ├── modules/
#     ├── linode/       # Linode instance module
#     │   ├── main.tf
#     │   ├── variables.tf
#     │   ├── outputs.tf
#     │   └── user_data.tftpl
#     └── volume/       # Volume module
#         ├── main.tf
#         ├── variables.tf
#         └── outputs.tf

# main.tf

# Generate a global unique suffix shared across all resources
# This ensures all VMs, firewalls, and related resources have the same identifier
resource "random_id" "global_suffix" {
  byte_length = 4

  keepers = {
    # Regenerate if project name changes
    project_name = var.project_name
  }
}

# =============================================================================
# DNS DOMAIN
# =============================================================================
# Domain is created/referenced here (not in DNS module) to break circular dependency:
# - ACME certificate needs domain to exist for DNS-01 challenge
# - DNS module needs instance IPs for A/AAAA records
# - Instances need ACME certificate for SSL

# Create new domain (if create_domain = true)
resource "linode_domain" "resilio" {
  count = var.create_domain ? 1 : 0

  type      = "master"
  domain    = var.tld
  soa_email = "admin@${var.tld}"
  tags      = ["terraform", "dns", var.project_name]

  lifecycle {
    prevent_destroy = true
  }
}

# Use existing domain (if create_domain = false)
data "linode_domain" "existing" {
  count = var.create_domain ? 0 : 1

  domain = var.tld
}

# Local for domain ID
locals {
  domain_id = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
}

# =============================================================================
# ACME / LET'S ENCRYPT SSL CERTIFICATES
# =============================================================================

# ACME provider registration for Let's Encrypt
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "resilio" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = "admin@${var.tld}"
}

# Let's Encrypt wildcard certificate for all Resilio instances
resource "acme_certificate" "resilio" {
  account_key_pem = acme_registration.resilio.account_key_pem
  common_name     = var.dns_include_project_name ? "${var.project_name}.${var.tld}" : var.tld
  subject_alternative_names = var.dns_include_project_name ? concat(
    ["*.${var.project_name}.${var.tld}"],
    [for region in var.regions : "${region}.${var.project_name}.${var.tld}"]
  ) : concat(
    ["*.${var.tld}"],
    [for region in var.regions : "${region}.${var.tld}"]
  )

  dns_challenge {
    provider = "linode"
    config = {
      LINODE_TOKEN               = var.linode_token
      LINODE_PROPAGATION_TIMEOUT = "1200" # 20 minutes for DNS propagation
      LINODE_POLLING_INTERVAL    = "30"   # Check every 30 seconds
      LINODE_TTL                 = "300"  # 5 minute TTL (Linode minimum)
    }
  }

  # Renew when less than 30 days remain
  min_days_remaining = 30
}

# Create per-folder data volumes for each region
# Each folder in resilio_folders gets its own independent volume
module "storage_volumes" {
  source = "./modules/volume"

  for_each = toset(var.regions) # ["us-east", "eu-west"]

  region       = each.key
  folders      = var.resilio_folders # Map of folder names to {key, size}
  project_name = var.project_name
  tags         = local.tags # Concat tags and tld
}

# =============================================================================
# BACKUP OBJECT STORAGE
# =============================================================================

# Create and manage Object Storage buckets for backups
# Note: Buckets are created when backup_storage_regions is non-empty, regardless of backup_enabled.
# This prevents accidental bucket destruction when toggling backup_enabled.
# The backup_enabled variable only controls whether backup scripts run on instances.
module "backup_storage" {
  source = "./modules/object-storage"
  count  = length(var.backup_storage_regions) > 0 ? 1 : 0

  project_name   = var.project_name
  suffix         = random_id.global_suffix.hex
  bucket_prefix  = var.backup_bucket_prefix
  backup_regions = var.backup_storage_regions

  enable_versioning = var.backup_versioning
  retention_days    = var.backup_retention_days
  tags              = local.tags
}

# Local values for backup configuration
# Handles both Terraform-managed (backup_enabled=true) and legacy manual configuration
locals {
  # Determine effective backup configuration
  backup_access_key = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].access_key : ""
  ) : var.object_storage_access_key

  backup_secret_key = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].secret_key : ""
  ) : var.object_storage_secret_key

  backup_buckets = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].buckets : {}
  ) : {}

  backup_primary_endpoint = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].primary_endpoint : ""
  ) : var.object_storage_endpoint

  backup_primary_bucket = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].primary_bucket.name : ""
  ) : var.object_storage_bucket

  # Determine which regions should run backups
  # Use new variable if set, fall back to legacy variable
  effective_backup_source_regions = length(var.backup_source_regions) > 0 ? var.backup_source_regions : var.backup_regions

  # Backup configuration to pass to instances
  backup_config = {
    enabled          = var.backup_enabled || var.object_storage_access_key != "CHANGEME"
    mode             = var.backup_mode
    schedule         = var.backup_schedule
    transfers        = var.backup_transfers
    bandwidth_limit  = var.backup_bandwidth_limit
    versioning       = var.backup_versioning
    retention_days   = var.backup_retention_days
    access_key       = local.backup_access_key
    secret_key       = local.backup_secret_key
    primary_endpoint = local.backup_primary_endpoint
    primary_bucket   = local.backup_primary_bucket
    all_buckets      = local.backup_buckets
  }
}

# =============================================================================
# FIREWALLS
# =============================================================================

# Create separate firewalls for jumpbox and resilio instances
# Jumpbox firewall - allows SSH from external network
module "jumpbox_firewall" {
  source = "./modules/jumpbox-firewall"

  project_name = var.project_name
  suffix       = random_id.global_suffix.hex # Use global suffix
  # Use auto-detected IP if allowed_ssh_cidr is not specified
  allowed_ssh_cidr = var.allowed_ssh_cidr != null ? var.allowed_ssh_cidr : local.current_ip_cidr
  tags             = local.tags # Concat tags and tld
}

# Resilio firewall - allows SSH from jumpbox and inter-instance communication
# Created with empty rules initially to avoid circular dependency
module "resilio_firewall" {
  source = "./modules/resilio-firewall"

  # Start with empty IPs - rules will be added via terraform_data resource below
  linode_ipv4  = []
  linode_ipv6  = []
  jumpbox_ipv4 = null
  jumpbox_ipv6 = null

  project_name = var.project_name
  suffix       = random_id.global_suffix.hex # Use global suffix
  tags         = local.tags                  # Concat tags and tld
}

# Create jumpbox instance (bastion host for secure access)
module "jumpbox" {
  source = "./modules/jumpbox"

  region         = var.jumpbox_region
  instance_type  = var.jumpbox_instance_type
  ssh_public_key = var.ssh_public_key
  project_name   = var.project_name
  suffix         = random_id.global_suffix.hex # Use global suffix
  firewall_id    = module.jumpbox_firewall.firewall_id
  tags           = local.tags
}

module "linode_instances" {
  source = "./modules/linode"

  for_each = toset(var.regions)

  region         = each.key          # "us-east"
  instance_type  = var.instance_type # "g6-standard-2"
  ssh_public_key = var.ssh_public_key
  project_name   = var.project_name            # "resilio-sync"
  suffix         = random_id.global_suffix.hex # Use global suffix

  include_project_name_in_hostname = var.dns_include_project_name

  # Per-folder volume configuration (new)
  resilio_folders = var.resilio_folders                      # Map of folder names to {key, size}
  folder_volumes  = module.storage_volumes[each.key].volumes # Map of folder names to volume details

  # Deprecated - kept for backward compatibility
  resilio_folder_keys = var.resilio_folder_keys
  resilio_folder_key  = var.resilio_folder_key
  volume_id           = module.storage_volumes[each.key].volume_id

  resilio_license_key    = var.resilio_license_key
  ubuntu_advantage_token = var.ubuntu_advantage_token
  tld                    = var.tld

  firewall_id = module.resilio_firewall.firewall_id # Attach resilio firewall during creation

  # SSL certificate from Let's Encrypt
  ssl_certificate = acme_certificate.resilio.certificate_pem
  ssl_private_key = acme_certificate.resilio.private_key_pem
  ssl_issuer_cert = acme_certificate.resilio.issuer_pem

  # Backup configuration (Terraform-managed or legacy)
  backup_config = {
    enabled          = local.backup_config.enabled && contains(local.effective_backup_source_regions, each.key)
    mode             = local.backup_config.mode
    schedule         = local.backup_config.schedule
    transfers        = local.backup_config.transfers
    bandwidth_limit  = local.backup_config.bandwidth_limit
    versioning       = local.backup_config.versioning
    retention_days   = local.backup_config.retention_days
    access_key       = local.backup_config.access_key
    secret_key       = local.backup_config.secret_key
    primary_endpoint = local.backup_config.primary_endpoint
    primary_bucket   = local.backup_config.primary_bucket
    all_buckets      = local.backup_config.all_buckets
  }

  # Legacy variables (deprecated, kept for compatibility)
  object_storage_access_key = local.backup_access_key
  object_storage_secret_key = local.backup_secret_key
  object_storage_endpoint   = local.backup_primary_endpoint
  object_storage_bucket     = local.backup_primary_bucket
  enable_backup             = local.backup_config.enabled && contains(local.effective_backup_source_regions, each.key)

  tags = local.tags # Concat tags and tld
}

module "dns" {
  source = "./modules/dns"

  # Domain ID from domain created/referenced above
  domain_id = local.domain_id

  # Map of DNS records keyed by region (static, known at plan time)
  dns_records = {
    for region, inst in module.linode_instances : region => {
      ipv4 = one(inst.ipv4_address) # Extract single IP from set
      ipv6 = inst.ipv6_address      # Already a string
    }
  }

  project_name         = var.project_name
  include_project_name = var.dns_include_project_name
}

# Local values for firewall rule updates
locals {
  jumpbox_ip           = module.jumpbox.ipv4_address
  resilio_instance_ips = [for inst in module.linode_instances : tolist(inst.ipv4_address)[0]]
  resilio_firewall_id  = module.resilio_firewall.firewall_id
}

# Update resilio firewall rules after instances are created
# This uses terraform_data (modern replacement for null_resource)
resource "terraform_data" "update_resilio_firewall" {
  # Trigger update whenever IPs or firewall ID changes
  # Bump version to force re-execution if needed
  triggers_replace = {
    version      = "3" # Increment this to force firewall rules update
    jumpbox_ip   = local.jumpbox_ip
    instance_ips = join(",", local.resilio_instance_ips)
    firewall_id  = local.resilio_firewall_id
  }

  # Update firewall rules using Linode API
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Updating resilio firewall rules..."

      # Prepare variables
      FIREWALL_ID="${local.resilio_firewall_id}"
      JUMPBOX_IP="${local.jumpbox_ip}"
      INSTANCE_IPS='${jsonencode(local.resilio_instance_ips)}'

      # Validate that we have the required IPs
      if [ -z "$JUMPBOX_IP" ]; then
        echo "❌ ERROR: Jumpbox IP is empty. Cannot update firewall rules."
        exit 1
      fi

      if [ "$INSTANCE_IPS" = "[]" ] || [ -z "$INSTANCE_IPS" ]; then
        echo "❌ ERROR: No Resilio instance IPs found. Cannot update firewall rules."
        echo "   This usually means the Resilio instances haven't been created yet."
        exit 1
      fi

      echo "📋 Firewall update details:"
      echo "   Firewall ID: $FIREWALL_ID"
      echo "   Jumpbox IP: $JUMPBOX_IP"
      echo "   Instance IPs: $(echo $INSTANCE_IPS | jq -r '.[]' | tr '\n' ' ')"
      echo ""

      # Create rules JSON
      cat > /tmp/resilio-fw-$${FIREWALL_ID}.json <<RULES_EOF
{
  "inbound": [
    {
      "label": "jumpbox-to-resilio-ssh",
      "action": "ACCEPT",
      "protocol": "TCP",
      "ports": "22,2022",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "jumpbox-to-resilio-webui",
      "action": "ACCEPT",
      "protocol": "TCP",
      "ports": "8888",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "jumpbox-to-resilio-ping",
      "action": "ACCEPT",
      "protocol": "ICMP",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "resilio-all-tcp",
      "action": "ACCEPT",
      "protocol": "TCP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    },
    {
      "label": "resilio-all-udp",
      "action": "ACCEPT",
      "protocol": "UDP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    },
    {
      "label": "resilio-all-icmp",
      "action": "ACCEPT",
      "protocol": "ICMP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    }
  ],
  "inbound_policy": "DROP",
  "outbound_policy": "ACCEPT"
}
RULES_EOF

      # Update firewall
      echo "🔧 Calling Linode API to update firewall $${FIREWALL_ID}..."
      RESPONSE=$(curl -s -w "\n%%{http_code}" -X PUT \
        -H "Authorization: Bearer ${var.linode_token}" \
        -H "Content-Type: application/json" \
        -d @/tmp/resilio-fw-$${FIREWALL_ID}.json \
        "https://api.linode.com/v4/networking/firewalls/$${FIREWALL_ID}/rules")

      HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
      BODY=$(echo "$RESPONSE" | sed '$d')

      # Check response
      if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ Resilio firewall rules updated successfully!"
        echo ""
        echo "Applied rules:"
        echo "   • Allow SSH (ports 22, 2022) from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow HTTPS Web UI (port 8888) from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow ICMP from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow all TCP traffic between Resilio instances"
        echo "   • Allow all UDP traffic between Resilio instances"
        echo "   • Allow ICMP between Resilio instances"
        echo "   • Instance IPs: $(echo $${INSTANCE_IPS} | jq -r '.[]' | tr '\n' ' ')"
        echo ""
        echo "Firewall ID: $${FIREWALL_ID}"
      else
        echo "❌ Failed to update firewall rules (HTTP $${HTTP_CODE})"
        echo ""
        echo "API Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        echo ""
        echo "Generated rules file saved at: /tmp/resilio-fw-$${FIREWALL_ID}.json"
        echo "You can inspect it for debugging or apply manually with:"
        echo "  curl -X PUT -H 'Authorization: Bearer \$LINODE_TOKEN' \\"
        echo "       -H 'Content-Type: application/json' \\"
        echo "       -d @/tmp/resilio-fw-$${FIREWALL_ID}.json \\"
        echo "       https://api.linode.com/v4/networking/firewalls/$${FIREWALL_ID}/rules"
        exit 1
      fi

      # Clean up
      rm -f /tmp/resilio-fw-$${FIREWALL_ID}.json
    EOT

    interpreter = ["bash", "-c"]
  }

  # Ensure instances are created before updating firewall
  depends_on = [
    module.jumpbox,
    module.linode_instances,
    module.resilio_firewall
  ]
}

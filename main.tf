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

# Create a data volume for each region
module "storage_volumes" {
  source = "./modules/volume"

  for_each = toset(var.regions) # ["us-east", "eu-west"]

  region       = each.key
  size         = var.volume_size
  project_name = var.project_name
  tags         = local.tags # Concat tags and tld
}

# Create separate firewalls for jumpbox and resilio instances
# Jumpbox firewall - allows SSH from external network
module "jumpbox_firewall" {
  source = "./modules/jumpbox-firewall"

  project_name = var.project_name
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
  tags         = local.tags # Concat tags and tld
}

# Create jumpbox instance (bastion host for secure access)
module "jumpbox" {
  source = "./modules/jumpbox"

  region         = var.jumpbox_region
  instance_type  = var.jumpbox_instance_type
  ssh_public_key = var.ssh_public_key
  project_name   = var.project_name
  firewall_id    = module.jumpbox_firewall.firewall_id
  tags           = local.tags
}

module "linode_instances" {
  source = "./modules/linode"

  for_each = toset(var.regions)

  region                 = each.key          # "us-east"
  instance_type          = var.instance_type # "g6-standard-2"
  ssh_public_key         = var.ssh_public_key
  project_name           = var.project_name # "resilio-sync"
  resilio_folder_keys    = var.resilio_folder_keys
  resilio_folder_key     = var.resilio_folder_key # Backward compatibility
  resilio_license_key    = var.resilio_license_key
  ubuntu_advantage_token = var.ubuntu_advantage_token
  tld                    = var.tld

  volume_id   = module.storage_volumes[each.key].volume_id
  firewall_id = module.resilio_firewall.firewall_id # Attach resilio firewall during creation

  # Object Storage for backups
  object_storage_access_key = var.object_storage_access_key
  object_storage_secret_key = var.object_storage_secret_key
  object_storage_endpoint   = var.object_storage_endpoint

  tags = local.tags # Concat tags and tld
}

module "dns" {
  source = "./modules/dns"

  # Map of DNS records keyed by region (static, known at plan time)
  dns_records = {
    for region, inst in module.linode_instances : region => {
      ipv4 = one(inst.ipv4_address) # Extract single IP from set
      ipv6 = inst.ipv6_address      # Already a string
    }
  }

  tld           = var.tld
  create_domain = var.create_domain
  project_name  = var.project_name
  tags          = local.tags # Concat tags and tld
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

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
module "resilio_firewall" {
  source = "./modules/resilio-firewall"

  # Handle circular dependency: On first apply, these will be empty/null.
  # On subsequent applies, they'll be populated with actual IPs.
  # Use try() to gracefully handle when instances don't exist yet.
  linode_ipv4  = try([for inst in module.linode_instances : tolist(inst.ipv4_address)[0]], [])
  linode_ipv6  = try([for inst in module.linode_instances : inst.ipv6_address], [])
  jumpbox_ipv4 = try(module.jumpbox.ipv4_address, null)
  jumpbox_ipv6 = try(module.jumpbox.ipv6_address, null)

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
  resilio_folder_key     = var.resilio_folder_key
  resilio_license_key    = var.resilio_license_key
  ubuntu_advantage_token = var.ubuntu_advantage_token
  tld                    = var.tld

  volume_id   = module.storage_volumes[each.key].volume_id
  firewall_id = module.resilio_firewall.firewall_id # Attach resilio firewall during creation

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

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
  tags = local.tags # Concat tags and tld
}

# Create a firewall first (before instances)
module "firewall" {
  source = "./modules/firewall"

  # Initial creation with just SSH rules - will be updated after instances are created
  linode_ipv4 = []  # Empty initially, will be updated later
  linode_ipv6 = []  # Empty initially, will be updated later

  project_name = var.project_name
  allowed_ssh_cidr = var.allowed_ssh_cidr
  tags = local.tags # Concat tags and tld
}

# Create jumpbox instance (bastion host for secure access)
module "jumpbox" {
  source = "./modules/jumpbox"

  region          = var.jumpbox_region
  instance_type   = var.jumpbox_instance_type
  ssh_public_key  = var.ssh_public_key
  project_name    = var.project_name
  firewall_id     = module.firewall.firewall_id
  tags            = local.tags
}

module "linode_instances" {
  source = "./modules/linode"

  for_each = toset(var.regions)

  region             = each.key # "us-east"
  instance_type      = var.instance_type # "g6-standard-2"
  ssh_public_key     = var.ssh_public_key
  project_name       = var.project_name # "resilio-sync"
  resilio_folder_key = var.resilio_folder_key
  resilio_license_key = var.resilio_license_key
  ubuntu_advantage_token = var.ubuntu_advantage_token
  tld = var.tld

  volume_id = module.storage_volumes[each.key].volume_id
  firewall_id = module.firewall.firewall_id  # Attach firewall during creation

  tags = local.tags # Concat tags and tld
}

module "dns" {
  source = "./modules/dns"

  # Map of DNS records keyed by region (static, known at plan time)
  dns_records = {
    for region, inst in module.linode_instances : region => {
      ipv4 = one(inst.ipv4_address)  # Extract single IP from set
      ipv6 = inst.ipv6_address        # Already a string
    }
  }

  tld = var.tld
  create_domain = var.create_domain
  project_name = var.project_name
  tags = local.tags # Concat tags and tld
}
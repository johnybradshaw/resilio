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
  
  tags = local.tags # Concat tags and tld
}

# Create a data volume for each region
module "storage_volumes" {
  source = "./modules/volume"
  
  for_each = toset(var.regions) # ["us-east", "eu-west"]
  
  region       = each.key
  size         = var.volume_size
  project_name = var.project_name
  tags = local.tags # Concat tags and tld
}

# Create a firewall
module "firewall" {
  source = "./modules/firewall"

  # Collect instance IDs
  linode_id   = [
    for inst in values(module.linode_instances) :
    inst.instance_id
  ]

  # Collect instance IPv4 and IPv6 addresses
  linode_ipv4 = flatten([
    for inst in values(module.linode_instances) :
    inst.ipv4_address
  ])
  linode_ipv6 = flatten([
    for inst in values(module.linode_instances) :
    inst.ipv6_address
  ])

  project_name = var.project_name
  allowed_ssh_cidr = var.allowed_ssh_cidr
  tags = local.tags # Concat tags and tld
}

module "dns" {
  source = "./modules/dns"

  # Collect instance labels
  linode_label = [
    for inst in values(module.linode_instances) :
    inst.instance_label
  ]

  # same for IPs (only flatten if each inst.ipv4_address is itself a list)
  linode_ipv4 = flatten([
    for inst in values(module.linode_instances) :
    inst.ipv4_address
  ])
  linode_ipv6 = flatten([
    for inst in values(module.linode_instances) :
    inst.ipv6_address
  ])

  tld = var.tld
  create_domain = var.create_domain
  project_name = var.project_name
  tags = local.tags # Concat tags and tld
}
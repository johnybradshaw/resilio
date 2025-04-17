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
}

module "storage_volumes" {
  source = "./modules/volume"
  
  for_each = toset(var.regions)
  
  region       = each.key
  size         = var.volume_size
  project_name = var.project_name
}

module "firewall" {
  source = "./modules/firewall"

  # pull the map of module objects into a list...
  linode_id   = [
    for inst in values(module.linode_instances) :
    inst.instance_id
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

  project_name = var.project_name
}

module "dns" {
  source = "./modules/dns"


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
  project_name = var.project_name
}
# Resilio

A Terraform-based solution to deploy Resilio Sync on Linode across multiple regions, with modular infrastructure for compute, storage, networking, and DNS management.

## Features

- **Multi-region Linode Instances** (`module.linode_instances`), each bootstrapped with a comprehensive Cloud-Init template for Resilio Sync installation and hardening.
- **Attaching Block Storage Volumes** via `module.volume`, with encryption-ready configuration and lifecycle protection.
- **Linode Firewall** policies to lock down inbound traffic (SSH limited to your IP, ICMP, inter-node traffic) while allowing outbound connectivity.
- **DNS Management** through `module.dns`, automatically creating A and AAAA records for each instance under your chosen TLD.

## Prerequisites

- [Terraform](https://www.terraform.io/) **>= 1.0.0** (required providers declared in `provider.tf`).
- A **Linode API token** with permissions to create instances, volumes, firewalls, and domains.
- Your **SSH public key**, Resilio Sync folder key, and license key. Sensitive values are passed via variables.

## Quick Start

1. **Clone the repository**  

   ```bash
   git clone https://github.com/johnybradshaw/resilio.git
   cd resilio
   ```

2. **Configure variables**  
   Copy the example file and fill in your values:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars to add:
   # linode_token, ssh_public_key, resilio_folder_key, resilio_license_key, tld, etc.
   ```

3. **Initialize Terraform**  

   ```bash
   terraform init
   ```

4. **Plan and apply**  

   ```bash
   terraform plan
   terraform apply
   ```

After a successful apply, you’ll see outputs including the public IPv4/IPv6 addresses and FQDNs of each Resilio Sync instance, the Linode Domain ID, volume IDs, and firewall IDs.

## Repository Structure

```
.
├── modules
│   ├── dns           # Manages Linode Domain and DNS records
│   ├── firewall      # Configures Linode Firewall rules
│   ├── linode        # Provisions Linode Instances with cloud-init
│   └── volume        # Creates and manages Linode Volumes
├── cloud-init.tpl    # Rich cloud-init template applied to each instance
├── provider.tf       # Provider setup (Linode)
├── variables.tf      # Root module input variables
├── outputs.tf        # Root module outputs
├── terraform.tfvars.example
└── LICENSE           # GPL-3.0
```

## Input Variables

| Name                    | Description                                         | Type             | Default                          |
|-------------------------|-----------------------------------------------------|------------------|----------------------------------|
| `linode_token`          | Linode API token                                    | `string`         | —                                |
| `regions`               | List of Linode regions to deploy to                 | `list(string)`   | `["us-east", "eu-west"]`         |
| `ssh_public_key`        | SSH public key for instance access                  | `string`         | —                                |
| `instance_type`         | Linode instance type                                | `string`         | `"g6-standard-1"`                |
| `volume_size`           | Size of the storage volume in GB                    | `number`         | `20`                             |
| `project_name`          | Name prefix for all resources                       | `string`         | `"resilio-sync"`                 |
| `resilio_folder_key`    | Resilio Sync folder key (sensitive)                 | `string`         | —                                |
| `resilio_license_key`   | Resilio Sync license key (sensitive)                | `string`         | —                                |
| `ubuntu_advantage_token`| Ubuntu Advantage token (sensitive)                  | `string`         | —                                |
| `tld`                   | Top-Level Domain for DNS records                    | `string`         | —                                |
| `tags`                  | Tags to apply to all resources                      | `list(string)`   | `["deployment: terraform","app: resilio"]` |

## Outputs

- **instance_ips**: Map of region → `{ ipv4, ipv6, fqdn }`
- **instance_ids**: Map of region → Linode instance ID
- **domain_id**: Linode Domain ID for your TLD
- **volume_id**: Block storage volume ID

## License

This project is licensed under the [GPL-3.0](LICENSE) license.

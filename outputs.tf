output "instance_ips" {
  description = "IPv4 and IPv6 addresses of the created instances"
  value = {
    for region, instance in module.linode_instances : region => {
      # convert the single‐element set to a list, grab index 0
      ipv4 = tolist(instance.ipv4_address)[0]

      # strip off the /128 on the CIDR
      ipv6 = replace(instance.ipv6_address, "/128", "")

      # display fqdn
      fqdn = "${instance.instance_label}.${var.tld}"
    }
  }
}

output "instance_ids" {
  description = "IDs of the created instances"
  value = {
    for region, instance in module.linode_instances : region => instance.instance_id
  }
}

output "volume_ids" {
  description = "IDs of the created storage volumes"
  value = {
    for region, volume in module.storage_volumes : region => volume.volume_id
  }
}

output "firewall_id" {
  description = "ID of the firewall protecting all instances"
  value       = module.firewall.firewall_id
}

output "domain_id" {
  description = "ID of the created DNS domain"
  value       = module.dns.domain_id
}

output "dns_nameservers" {
  description = "Nameservers for the DNS domain (configure these at your domain registrar)"
  value       = module.dns.nameservers
}

output "root_passwords" {
  description = "Root passwords for instances (use 'terraform output -raw root_passwords' to view)"
  value = {
    for region, instance in module.linode_instances : region => instance.root_password
  }
  sensitive = true
}

output "ssh_connection_strings" {
  description = "SSH connection strings for easy access to instances"
  value = var.enable_jumphost ? {
    for region, instance in module.linode_instances : region =>
      "ssh -J ${var.admin_username}@${tolist(module.jumphost[0].jumphost_ipv4)[0]} ${var.admin_username}@${tolist(instance.ipv4_address)[0]}"
  } : {
    for region, instance in module.linode_instances : region =>
      "ssh ${var.admin_username}@${tolist(instance.ipv4_address)[0]}"
  }
}

# Jumphost outputs (when enabled)
output "jumphost_ip" {
  description = "IPv4 address of the jumphost (use this to SSH into Resilio instances)"
  value       = var.enable_jumphost ? tolist(module.jumphost[0].jumphost_ipv4)[0] : null
}

output "jumphost_connection" {
  description = "SSH connection string for jumphost"
  value       = var.enable_jumphost ? "ssh ${var.admin_username}@${tolist(module.jumphost[0].jumphost_ipv4)[0]}" : "Jumphost disabled"
}

output "jumphost_password" {
  description = "Root password for jumphost (emergency use only)"
  value       = var.enable_jumphost ? module.jumphost[0].jumphost_password : null
  sensitive   = true
}
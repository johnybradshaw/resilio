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

output "jumpbox_firewall_id" {
  description = "ID of the firewall protecting the jumpbox"
  value       = module.jumpbox_firewall.firewall_id
}

output "resilio_firewall_id" {
  description = "ID of the firewall protecting resilio instances"
  value       = module.resilio_firewall.firewall_id
}

output "domain_id" {
  description = "ID of the created DNS domain"
  value       = module.dns.domain_id
}

output "dns_nameservers" {
  description = "Nameservers for the DNS domain (configure these at your domain registrar)"
  value       = module.dns.nameservers
}

output "ssh_connection_strings" {
  description = "SSH connection strings to resilio instances via jumpbox (uses ac-user with SSH key authentication)"
  value = {
    for region, instance in module.linode_instances : region =>
    "ssh -J ac-user@${module.jumpbox.ipv4_address} ac-user@${tolist(instance.ipv4_address)[0]}"
  }
}

output "jumpbox_ip" {
  description = "IP address of the jumpbox (bastion host)"
  value       = module.jumpbox.ipv4_address
}

output "jumpbox_ssh" {
  description = "SSH connection string for the jumpbox"
  value       = module.jumpbox.ssh_connection_string
}
output "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access (shows auto-detected IP if not manually set)"
  value       = var.allowed_ssh_cidr != null ? var.allowed_ssh_cidr : local.current_ip_cidr
}

output "firewall_configuration" {
  description = "Firewall configuration status"
  value       = "✅ Two separate firewalls configured: jumpbox-firewall (static rules) and resilio-firewall (auto-updated via Linode API)"
}

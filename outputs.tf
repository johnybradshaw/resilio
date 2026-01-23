output "instance_ips" {
  description = "IPv4 and IPv6 addresses of the created instances"
  value = {
    for region, instance in module.linode_instances : region => {
      # convert the single‐element set to a list, grab index 0
      ipv4 = tolist(instance.ipv4_address)[0]

      # strip off the /128 on the CIDR
      ipv6 = replace(instance.ipv6_address, "/128", "")

      # display fqdn (matches DNS record, e.g., us-east.resilio-sync.domain.tld)
      fqdn = "${instance.hostname}.${var.tld}"
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
  description = "ID of the DNS domain (created or existing)"
  value       = local.domain_id
}

output "dns_nameservers" {
  description = "Nameservers for the DNS domain (configure these at your domain registrar)"
  value = [
    "ns1.linode.com",
    "ns2.linode.com",
    "ns3.linode.com",
    "ns4.linode.com",
    "ns5.linode.com"
  ]
}

output "ssh_connection_strings" {
  description = "SSH connection strings to resilio instances via jumpbox (uses cloud_user with SSH key authentication)"
  value = {
    for region, instance in module.linode_instances : region =>
    "ssh -J ${var.cloud_user}@${module.jumpbox.ipv4_address} ${var.cloud_user}@${tolist(instance.ipv4_address)[0]}"
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

output "global_suffix" {
  description = "Global suffix shared across all VMs and resources (useful for identifying related resources)"
  value       = random_id.global_suffix.hex
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = acme_certificate.resilio.certificate_domain
}

output "ssl_certificate_expiry" {
  description = "SSL certificate expiry date"
  value       = acme_certificate.resilio.certificate_not_after
}

# Backup outputs
output "backup_enabled" {
  description = "Whether Terraform-managed backups are enabled"
  value       = var.backup_enabled
}

output "backup_buckets" {
  description = "Backup storage buckets by region (only when backup_enabled=true)"
  value       = var.backup_enabled && length(module.backup_storage) > 0 ? module.backup_storage[0].buckets : {}
}

output "backup_mode" {
  description = "Backup scheduling mode (scheduled, realtime, or hybrid)"
  value       = var.backup_mode
}

output "backup_source_regions" {
  description = "Regions that will run backups to Object Storage"
  value       = local.effective_backup_source_regions
}

output "backup_rehydrate_command" {
  description = "Command to restore from backup on a new VM"
  value       = var.backup_enabled || var.object_storage_access_key != "CHANGEME" ? "sudo /usr/local/bin/resilio-rehydrate.sh --list" : "Backups not configured"
  sensitive   = true
}

# VM Credentials
output "vm_credentials" {
  description = "Credentials for VM access (root, cloud_user) and Resilio web UI per region"
  sensitive   = true
  value = {
    for region, instance in module.linode_instances : region => {
      root_password  = instance.root_password
      user_password  = instance.user_password
      webui_username = "admin"
      webui_password = instance.webui_password
      webui_url      = "https://${instance.hostname}.${var.tld}:8888"
    }
  }
}

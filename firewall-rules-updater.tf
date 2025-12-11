# firewall-rules-updater.tf
# Automatically updates firewall rules after instances are created
# This breaks the circular dependency by using the Linode API directly

# Collect all instance IPs for firewall rules
locals {
  jumpbox_ip           = module.jumpbox.ipv4_address
  resilio_instance_ips = [for inst in module.linode_instances : tolist(inst.ipv4_address)[0]]
  resilio_firewall_id  = module.resilio_firewall.firewall_id
}

# Update resilio firewall rules after instances are created
# Jumpbox firewall doesn't need updates as it only has static rules
resource "null_resource" "update_resilio_firewall_rules" {
  # Depend on all instances being created
  depends_on = [
    module.jumpbox,
    module.linode_instances
  ]

  # Trigger update whenever IPs change
  triggers = {
    jumpbox_ip    = local.jumpbox_ip
    instance_ips  = join(",", local.resilio_instance_ips)
    firewall_id   = local.resilio_firewall_id
  }

  # Update resilio firewall rules using Linode API
  provisioner "local-exec" {
    command = <<-EOT
      # Get resilio firewall ID
      FIREWALL_ID="${local.resilio_firewall_id}"

      # Prepare IP lists
      JUMPBOX_IP="${local.jumpbox_ip}"
      INSTANCE_IPS='${jsonencode(local.resilio_instance_ips)}'

      # Create rules JSON (jumpbox → resilio SSH + inter-instance communication)
      cat > /tmp/resilio-firewall-update-$${FIREWALL_ID}.json << 'RULES_EOF'
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
      
      # Update resilio firewall using Linode API
      curl -X PUT \
        -H "Authorization: Bearer ${var.linode_token}" \
        -H "Content-Type: application/json" \
        -d @/tmp/resilio-firewall-update-$${FIREWALL_ID}.json \
        "https://api.linode.com/v4/networking/firewalls/$${FIREWALL_ID}/rules"

      # Clean up
      rm -f /tmp/resilio-firewall-update-$${FIREWALL_ID}.json

      echo "✅ Resilio firewall rules updated automatically!"
    EOT
    
    interpreter = ["bash", "-c"]
  }
}

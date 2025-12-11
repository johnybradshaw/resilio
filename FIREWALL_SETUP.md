# Firewall Setup

## Overview

This infrastructure uses two separate firewalls:

1. **Jumpbox Firewall** (`jumpbox-firewall`): Protects the jumpbox bastion host
2. **Resilio Firewall** (`resilio-firewall`): Protects resilio sync instances

## Firewall Rules

### Jumpbox Firewall
- **External → Jumpbox**: SSH (22, 2022) and ICMP from allowed CIDR
- **Inbound Policy**: DROP (default deny)
- **Outbound Policy**: ACCEPT (allow all outbound)

### Resilio Firewall
- **Jumpbox → Resilio**: SSH (22, 2022) and ICMP
- **Resilio ↔ Resilio**: All TCP, UDP, and ICMP traffic between instances
- **Inbound Policy**: DROP (default deny)
- **Outbound Policy**: ACCEPT (allow all outbound)

## Deployment Process

Due to Terraform's circular dependency handling (firewall needs instance IPs, instances need firewall_id), the deployment requires **two applies**:

### First Apply
Creates infrastructure with empty firewall rules:
```bash
terraform apply
```

This creates:
- Jumpbox firewall (with rules - no dependencies)
- Resilio firewall (with NO rules yet - empty IPs)
- Jumpbox instance
- Resilio instances

### Second Apply
Updates the resilio firewall with actual instance IPs:
```bash
terraform apply
```

This updates:
- Resilio firewall rules with jumpbox IP and resilio instance IPs

## Verification

After the second apply, verify firewall rules are in place:

1. **Check Terraform state**:
   ```bash
   terraform state show module.resilio_firewall.linode_firewall.resilio
   ```

2. **Check Linode Console**:
   - Navigate to Firewalls in Linode Cloud Manager
   - Find `resilio-sync-resilio-fw-XXXX`
   - Verify inbound rules are present

## Architecture

```
External Network
       ↓ (SSH/ICMP from allowed_cidr)
   Jumpbox Firewall
       ↓
    Jumpbox
       ↓ (SSH/ICMP)
 Resilio Firewall
       ↓
Resilio Instances ←→ (TCP/UDP/ICMP) ←→ Resilio Instances
```

## Troubleshooting

**Q: Resilio firewall shows no rules after first apply**
A: This is expected. Run `terraform apply` a second time to populate the rules.

**Q: Can I avoid the two-apply process?**
A: Use targeted applies:
```bash
terraform apply -target=module.jumpbox_firewall -target=module.resilio_firewall
terraform apply
```

**Q: Rules not updating after IP changes**
A: Run `terraform apply` to update firewall rules with new IPs.

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

The deployment handles the circular dependency automatically using a `terraform_data` resource:

### Single Apply
Run terraform apply once:
```bash
terraform apply
```

This automatically:
1. Creates jumpbox firewall with rules ✅
2. Creates resilio firewall with no rules (initially)
3. Creates jumpbox and resilio instances
4. **Automatically updates** resilio firewall rules via Linode API with actual IPs ✅

The `terraform_data.update_resilio_firewall` resource runs a provisioner after instances are created that:
- Collects jumpbox and instance IPs
- Calls Linode API to update firewall rules
- Provides detailed success/failure output

## Verification

After apply completes, verify firewall rules are in place:

1. **Check apply output**: Look for the success message:
   ```
   ✅ Resilio firewall rules updated successfully!
   ```

2. **Check Linode Console**:
   - Navigate to Firewalls in Linode Cloud Manager
   - Find `resilio-sync-resilio-fw-XXXX`
   - Verify inbound rules are present:
     - jumpbox-to-resilio-ssh
     - jumpbox-to-resilio-ping
     - resilio-all-tcp
     - resilio-all-udp
     - resilio-all-icmp

3. **Test connectivity**:
   ```bash
   # SSH to jumpbox (should work)
   ssh ac-user@<jumpbox-ip>

   # From jumpbox, SSH to resilio instance (should work)
   ssh ac-user@<resilio-ip>
   ```

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

**Q: Firewall update failed during apply**
A: Check the error output from the provisioner. Common issues:
- `linode_token` not set or invalid
- API rate limiting
- Network connectivity issues
Solution: Run `terraform apply` again to retry

**Q: Rules not visible immediately after apply**
A: The API update happens via provisioner, which runs after resource creation. Check:
1. Terraform output for "✅ Resilio firewall rules updated successfully!"
2. If update failed, check error message and retry

**Q: Want to force firewall rules update**
A: Taint the terraform_data resource:
```bash
terraform taint terraform_data.update_resilio_firewall
terraform apply
```

**Q: Rules not updating after IP changes**
A: The `terraform_data` resource automatically detects IP changes via triggers. Run:
```bash
terraform apply
```

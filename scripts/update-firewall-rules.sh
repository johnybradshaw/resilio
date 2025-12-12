#!/bin/bash
# scripts/update-firewall-rules.sh
#
# Helper script to update firewall rules with instance IPs after initial deployment
# Run this after: terraform apply
#
# This script reads instance IPs from terraform output and updates the firewall
# to allow inter-instance communication and jumpbox→resilio SSH access

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Firewall Rules Update Helper                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
    echo -e "${YELLOW}Error: terraform not found${NC}"
    exit 1
fi

echo -e "${GREEN}This script will update firewall rules to enable:${NC}"
echo "  • Jumpbox → Resilio SSH access"
echo "  • Resilio ↔ Resilio direct sync (no relay needed)"
echo ""

# Get instance IPs from terraform output
echo -e "${BLUE}Getting instance IPs from terraform...${NC}"
JUMPBOX_IP=$(terraform output -json jumpbox_ip 2>/dev/null | jq -r '.')
INSTANCE_IPS=$(terraform output -json instance_ips 2>/dev/null | jq -r '.[] | .ipv4' | tr '\n' ',' | sed 's/,$//')

if [ -z "$JUMPBOX_IP" ] || [ "$JUMPBOX_IP" == "null" ]; then
    echo -e "${YELLOW}Error: Could not get jumpbox IP from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Jumpbox IP: ${JUMPBOX_IP}${NC}"
echo -e "${GREEN}✓ Instance IPs: ${INSTANCE_IPS}${NC}"
echo ""

echo -e "${YELLOW}To complete firewall configuration, you have two options:${NC}"
echo ""
echo -e "${BLUE}Option 1: Use Linode Cloud Manager (Recommended)${NC}"
echo "  1. Go to: https://cloud.linode.com/firewalls"
echo "  2. Click on your firewall (resilio-sync-firewall-*)"
echo "  3. Add inbound rules:"
echo "     • Label: jumpbox-to-resilio-ssh"
echo "       Protocol: TCP, Ports: 22,2022"
echo "       Sources: ${JUMPBOX_IP}/32"
echo ""
echo "     • Label: resilio-all-tcp"
echo "       Protocol: TCP, Ports: All"
echo "       Sources: ${INSTANCE_IPS} (comma-separated /32 CIDRs)"
echo ""
echo "     • Label: resilio-all-udp"
echo "       Protocol: UDP, Ports: All"
echo "       Sources: ${INSTANCE_IPS} (comma-separated /32 CIDRs)"
echo ""
echo -e "${BLUE}Option 2: Use Terraform (requires manual variable update)${NC}"
echo "  This is currently not automated due to circular dependencies."
echo "  Future enhancement: Support via separate firewall rule management."
echo ""

echo -e "${GREEN}After adding these rules, your setup will be complete!${NC}"

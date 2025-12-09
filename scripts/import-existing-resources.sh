#!/bin/bash
# scripts/import-existing-resources.sh
#
# Helper script to import existing Linode resources into Terraform state
# Use this when resources already exist in Linode but aren't in Terraform state
#
# Usage:
#   bash scripts/import-existing-resources.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Terraform Resource Import Helper                  ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Error: Terraform is not installed${NC}"
    exit 1
fi

# Check if linode-cli is installed
if ! command -v linode-cli &> /dev/null; then
    echo -e "${YELLOW}⚠ Warning: linode-cli is not installed${NC}"
    echo -e "  Install: ${BLUE}pip install linode-cli${NC}"
    echo -e "  This script can still help you, but you'll need to find IDs manually."
    echo ""
fi

echo -e "${GREEN}This script helps import existing Linode resources into Terraform.${NC}"
echo ""
echo -e "Common scenarios:"
echo -e "  1. DNS domain already exists"
echo -e "  2. Volumes already exist"
echo -e "  3. Instances already exist"
echo ""

# Function to import DNS domain
import_dns_domain() {
    echo -e "${BLUE}═══ Import DNS Domain ═══${NC}"
    echo ""

    read -p "Enter domain name (e.g., aka.bradshaw.cloud): " DOMAIN

    if command -v linode-cli &> /dev/null; then
        echo -e "${YELLOW}Looking up domain ID...${NC}"
        DOMAIN_ID=$(linode-cli domains list --json | jq -r ".[] | select(.domain==\"$DOMAIN\") | .id")

        if [ -z "$DOMAIN_ID" ]; then
            echo -e "${RED}✗ Domain not found in Linode${NC}"
            return 1
        fi

        echo -e "${GREEN}✓ Found domain: $DOMAIN (ID: $DOMAIN_ID)${NC}"
    else
        read -p "Enter domain ID (from Linode Cloud Manager): " DOMAIN_ID
    fi

    echo ""
    echo -e "${YELLOW}Running: terraform import module.dns.linode_domain.resilio $DOMAIN_ID${NC}"

    if terraform import module.dns.linode_domain.resilio "$DOMAIN_ID"; then
        echo ""
        echo -e "${GREEN}✓ Successfully imported DNS domain!${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ Failed to import DNS domain${NC}"
        return 1
    fi
}

# Function to import volume
import_volume() {
    echo -e "${BLUE}═══ Import Volume ═══${NC}"
    echo ""

    read -p "Enter region (e.g., us-east, eu-west): " REGION

    if command -v linode-cli &> /dev/null; then
        echo -e "${YELLOW}Listing volumes in $REGION...${NC}"
        linode-cli volumes list --region "$REGION" --format "id,label,size,region" --text
        echo ""
    fi

    read -p "Enter volume ID: " VOLUME_ID

    echo ""
    echo -e "${YELLOW}Running: terraform import module.storage_volumes[\"$REGION\"].linode_volume.storage $VOLUME_ID${NC}"

    if terraform import "module.storage_volumes[\"$REGION\"].linode_volume.storage" "$VOLUME_ID"; then
        echo ""
        echo -e "${GREEN}✓ Successfully imported volume!${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ Failed to import volume${NC}"
        return 1
    fi
}

# Main menu
while true; do
    echo ""
    echo -e "${BLUE}What would you like to import?${NC}"
    echo "  1) DNS Domain"
    echo "  2) Volume"
    echo "  3) Exit"
    echo ""
    read -p "Choice: " CHOICE

    case $CHOICE in
        1)
            import_dns_domain
            ;;
        2)
            import_volume
            ;;
        3)
            echo -e "${GREEN}Done!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
done

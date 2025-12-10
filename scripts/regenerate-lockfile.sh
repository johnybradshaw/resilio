#!/bin/bash
# scripts/regenerate-lockfile.sh
#
# Regenerates the Terraform lock file with correct provider versions
# Run this after updating provider requirements to ensure lock file is current
#
# Usage:
#   bash scripts/regenerate-lockfile.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Terraform Lock File Regeneration Utility          ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Error: Terraform is not installed${NC}"
    exit 1
fi

echo -e "${YELLOW}Removing old lock file...${NC}"
rm -f .terraform.lock.hcl

echo -e "${YELLOW}Initializing Terraform with upgraded providers...${NC}"
terraform init -upgrade

echo ""
echo -e "${GREEN}✓ Lock file regenerated successfully!${NC}"
echo ""
echo -e "${BLUE}New provider versions:${NC}"
grep -A 2 "provider.*linode/linode" .terraform.lock.hcl || true
grep -A 2 "provider.*hashicorp/random" .terraform.lock.hcl || true
grep -A 2 "provider.*hashicorp/http" .terraform.lock.hcl || true

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "  1. Review the changes: ${YELLOW}git diff .terraform.lock.hcl${NC}"
echo -e "  2. Commit the updated lock file: ${YELLOW}git add .terraform.lock.hcl${NC}"
echo -e "  3. Push to repository: ${YELLOW}git commit -m 'Update provider lock file'${NC}"

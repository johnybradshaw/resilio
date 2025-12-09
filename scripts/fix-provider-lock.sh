#!/bin/bash
# scripts/fix-provider-lock.sh
#
# This script fixes the Terraform provider lock file issue where the locked
# provider version doesn't match the configured version constraint.
#
# The issue occurs when:
# - Lock file has linode/linode 2.37.0 with constraint ">= 2.5.0"
# - provider.tf now requires "~> 3.5" (version 3.5.x)
#
# Usage:
#   bash scripts/fix-provider-lock.sh
#   # OR for a clean start:
#   bash scripts/fix-provider-lock.sh --clean

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Terraform Provider Lock File Fix Utility          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Error: Terraform is not installed or not in PATH${NC}"
    echo "Install Terraform from: https://www.terraform.io/downloads"
    exit 1
fi

# Show current Terraform version
TERRAFORM_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
echo -e "${GREEN}✓ Terraform version: ${TERRAFORM_VERSION}${NC}"
echo ""

# Check for --clean flag
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}⚠ Clean mode: Removing existing .terraform directory and lock file${NC}"

    if [ -d ".terraform" ]; then
        echo -e "${BLUE}  Removing .terraform directory...${NC}"
        rm -rf .terraform
        echo -e "${GREEN}  ✓ Removed .terraform directory${NC}"
    fi

    if [ -f ".terraform.lock.hcl" ]; then
        echo -e "${BLUE}  Removing .terraform.lock.hcl file...${NC}"
        rm -f .terraform.lock.hcl
        echo -e "${GREEN}  ✓ Removed .terraform.lock.hcl file${NC}"
    fi

    echo ""
fi

# Show current provider requirements
echo -e "${BLUE}Current provider requirements from provider.tf:${NC}"
echo ""
grep -A 20 "required_providers" provider.tf | grep -E "^\s+(linode|random|http)\s*=" -A 2 || true
echo ""

# Check current lock file status
if [ -f ".terraform.lock.hcl" ]; then
    echo -e "${YELLOW}Current lock file versions:${NC}"
    grep -E "^provider.*linode/linode" .terraform.lock.hcl || echo "  (linode provider not found)"
    grep -A 1 "^provider.*linode/linode" .terraform.lock.hcl | grep "version" || true
    echo ""
fi

# Run terraform init -upgrade
echo -e "${BLUE}Running: terraform init -upgrade${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

if terraform init -upgrade; then
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Successfully upgraded provider lock file!${NC}"
    echo ""

    # Show new lock file versions
    if [ -f ".terraform.lock.hcl" ]; then
        echo -e "${GREEN}New lock file versions:${NC}"
        grep -E "^provider.*linode/linode" .terraform.lock.hcl || true
        grep -A 1 "^provider.*linode/linode" .terraform.lock.hcl | grep "version" || true
        echo ""
        grep -E "^provider.*hashicorp/random" .terraform.lock.hcl || true
        grep -A 1 "^provider.*hashicorp/random" .terraform.lock.hcl | grep "version" || true
        echo ""
        grep -E "^provider.*hashicorp/http" .terraform.lock.hcl || true
        grep -A 1 "^provider.*hashicorp/http" .terraform.lock.hcl | grep "version" || true
        echo ""
    fi

    echo -e "${GREEN}✓ You can now run Terraform commands:${NC}"
    echo -e "  ${YELLOW}terraform validate${NC}"
    echo -e "  ${YELLOW}terraform plan${NC}"
    echo -e "  ${YELLOW}terraform apply${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Failed to upgrade provider lock file${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo -e "  1. Try running with --clean flag:"
    echo -e "     ${BLUE}bash scripts/fix-provider-lock.sh --clean${NC}"
    echo ""
    echo -e "  2. Manually remove the lock file and .terraform directory:"
    echo -e "     ${BLUE}rm -rf .terraform .terraform.lock.hcl${NC}"
    echo -e "     ${BLUE}terraform init${NC}"
    echo ""
    echo -e "  3. Check your internet connection and Terraform registry access"
    echo ""
    echo -e "  4. Verify provider.tf has correct provider configuration"
    echo ""
    exit 1
fi

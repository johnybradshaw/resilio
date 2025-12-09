#!/bin/bash
# scripts/setup-backend-credentials.sh
#
# Helper script to set up Terraform backend credentials from 1Password
# This script exports the necessary environment variables for Terraform to use
# Linode Object Storage as a backend with encryption.
#
# Prerequisites:
# 1. Install 1Password CLI: https://developer.1password.com/docs/cli/get-started/
# 2. Sign in to 1Password: op signin
# 3. Store your credentials in 1Password with the following structure:
#    - Item: "linode-object-storage" in vault "Infrastructure"
#      - access_key_id: Your Linode Object Storage access key
#      - secret_access_key: Your Linode Object Storage secret key
#    - Item: "terraform-state-encryption" in vault "Infrastructure"
#      - encryption_key: 256-bit (32-byte) AES key, base64-encoded
#
# Usage:
#   source scripts/setup-backend-credentials.sh
#   # Then run your terraform commands
#   terraform init
#   terraform plan

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Terraform backend credentials from 1Password...${NC}"

# Check if 1Password CLI is installed
if ! command -v op &> /dev/null; then
    echo -e "${RED}Error: 1Password CLI (op) is not installed.${NC}"
    echo "Install it from: https://developer.1password.com/docs/cli/get-started/"
    return 1
fi

# Check if signed in to 1Password
if ! op account list &> /dev/null; then
    echo -e "${YELLOW}You need to sign in to 1Password first.${NC}"
    echo "Run: op signin"
    return 1
fi

# Configuration - adjust these to match your 1Password setup
VAULT_NAME="${OP_VAULT_NAME:-Infrastructure}"
OBJECT_STORAGE_ITEM="${OP_OBJECT_STORAGE_ITEM:-linode-object-storage}"
ENCRYPTION_ITEM="${OP_ENCRYPTION_ITEM:-terraform-state-encryption}"

echo -e "${GREEN}Retrieving credentials from 1Password...${NC}"

# Export AWS credentials (used by S3 backend for Linode Object Storage)
export AWS_ACCESS_KEY_ID=$(op read "op://${VAULT_NAME}/${OBJECT_STORAGE_ITEM}/access_key_id" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not retrieve access_key_id from 1Password${NC}"
    echo "Make sure the item 'op://${VAULT_NAME}/${OBJECT_STORAGE_ITEM}/access_key_id' exists"
    return 1
fi

export AWS_SECRET_ACCESS_KEY=$(op read "op://${VAULT_NAME}/${OBJECT_STORAGE_ITEM}/secret_access_key" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}Error: Could not retrieve secret_access_key from 1Password${NC}"
    echo "Make sure the item 'op://${VAULT_NAME}/${OBJECT_STORAGE_ITEM}/secret_access_key' exists"
    return 1
fi

# Optional: Export encryption key if you're using SSE-C
# export TF_VAR_backend_encryption_key=$(op read "op://${VAULT_NAME}/${ENCRYPTION_ITEM}/encryption_key" 2>/dev/null)
# if [ $? -ne 0 ] || [ -z "$TF_VAR_backend_encryption_key" ]; then
#     echo -e "${YELLOW}Warning: Could not retrieve encryption_key from 1Password${NC}"
#     echo "Continuing without encryption key. State file will use default encryption."
# fi

echo -e "${GREEN}✓ Credentials successfully loaded from 1Password${NC}"
echo -e "${GREEN}✓ AWS_ACCESS_KEY_ID is set${NC}"
echo -e "${GREEN}✓ AWS_SECRET_ACCESS_KEY is set${NC}"

# Optional: Show masked credentials for verification
echo -e "\n${YELLOW}Credentials (masked):${NC}"
echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:4}...${AWS_ACCESS_KEY_ID: -4}"
echo "  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:4}...${AWS_SECRET_ACCESS_KEY: -4}"

echo -e "\n${GREEN}You can now run Terraform commands with backend configured.${NC}"
echo -e "Example: ${YELLOW}terraform init${NC}"

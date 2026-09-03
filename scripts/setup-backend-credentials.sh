#!/usr/bin/env bash
# scripts/setup-backend-credentials.sh
#
# Loads Terraform backend credentials for Linode Object Storage from 1Password.
#
# This script must be SOURCED, not executed, so the exported variables persist
# in your shell:
#
#   source scripts/setup-backend-credentials.sh
#   terraform init -backend-config=backend.tfvars
#   terraform plan
#
# Expected 1Password item (see docs/BACKEND_SETUP.md for creation):
#   op://secrets.resilio/terraform-state-backend/access_key_id
#   op://secrets.resilio/terraform-state-backend/secret_access_key
#
# Override the vault or item via environment:
#   OP_VAULT_NAME  (default: secrets.resilio)
#   OP_ITEM_NAME   (default: terraform-state-backend)

# Guard: refuse to run as a subprocess, where the exports would be discarded.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: this script must be sourced, not executed." >&2
    echo "  Run: source ${0}" >&2
    exit 1
fi

_backend_creds_fail() {
    echo "Error: $1" >&2
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    return 1
}

VAULT_NAME="${OP_VAULT_NAME:-secrets.resilio}"
ITEM_NAME="${OP_ITEM_NAME:-terraform-state-backend}"

if ! command -v op >/dev/null 2>&1; then
    _backend_creds_fail "1Password CLI (op) is not installed. See https://developer.1password.com/docs/cli/get-started/"
    return $?
fi

if ! op whoami >/dev/null 2>&1; then
    _backend_creds_fail "not signed in to 1Password. Run: op signin"
    return $?
fi

# Read both secrets before exporting either, so a partial failure leaves the
# environment clean rather than half-configured.
_ak="$(op read "op://${VAULT_NAME}/${ITEM_NAME}/access_key_id" 2>/dev/null)" || _ak=""
_sk="$(op read "op://${VAULT_NAME}/${ITEM_NAME}/secret_access_key" 2>/dev/null)" || _sk=""

if [ -z "${_ak}" ]; then
    unset _ak _sk
    _backend_creds_fail "could not read op://${VAULT_NAME}/${ITEM_NAME}/access_key_id"
    return $?
fi

if [ -z "${_sk}" ]; then
    unset _ak _sk
    _backend_creds_fail "could not read op://${VAULT_NAME}/${ITEM_NAME}/secret_access_key"
    return $?
fi

export AWS_ACCESS_KEY_ID="${_ak}"
export AWS_SECRET_ACCESS_KEY="${_sk}"
unset _ak _sk

# The S3 backend resolves region from backend.tfvars; this only assists any
# aws/s3cmd calls made by hand in the same shell.
export AWS_REGION="${AWS_REGION:-fr-par-1}"

echo "Backend credentials loaded from op://${VAULT_NAME}/${ITEM_NAME}"
echo "  AWS_ACCESS_KEY_ID     set (${#AWS_ACCESS_KEY_ID} chars)"
echo "  AWS_SECRET_ACCESS_KEY set (${#AWS_SECRET_ACCESS_KEY} chars)"
echo
echo "Next: terraform init -backend-config=backend.tfvars"

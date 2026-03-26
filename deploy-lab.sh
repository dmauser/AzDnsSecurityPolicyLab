#!/bin/bash

# Azure DNS Security Policy Lab Deployment Script
# Deploys the lab using the Bicep template in infra/main.bicep.
# Designed for GitHub Codespaces — no additional prerequisites required.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " Azure DNS Security Policy Lab Deployment"
echo "=========================================="

# ── Read configuration ─────────────────────────────────────────────────────────
if [[ ! -f "$SCRIPT_DIR/answers.json" ]]; then
    echo "Error: answers.json not found."
    echo "Copy answers.json.template to answers.json and set your subscriptionId."
    exit 1
fi

SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$SCRIPT_DIR/answers.json")
RESOURCE_GROUP_NAME=$(jq -r '.resourceGroupName' "$SCRIPT_DIR/answers.json")

if [[ -z "$SUBSCRIPTION_ID" || "$SUBSCRIPTION_ID" == "null" || "$SUBSCRIPTION_ID" == "YOUR-SUBSCRIPTION-ID-HERE" ]]; then
    echo "Error: Set a valid subscriptionId in answers.json before deploying."
    exit 1
fi

# ── Password prompt ────────────────────────────────────────────────────────────
validate_password() {
    local p="$1"
    [[ ${#p} -ge 12 && ${#p} -le 123 ]] || { echo "Must be 12-123 characters."; return 1; }
    [[ "$p" =~ [A-Z] ]] || { echo "Must contain an uppercase letter."; return 1; }
    [[ "$p" =~ [a-z] ]] || { echo "Must contain a lowercase letter."; return 1; }
    [[ "$p" =~ [0-9] ]] || { echo "Must contain a number."; return 1; }
    [[ "$p" =~ [^a-zA-Z0-9] ]] || { echo "Must contain a special character."; return 1; }
}

echo ""
echo "Password Requirements: 12-123 chars, uppercase, lowercase, number, special char"
echo ""
while true; do
    read -s -p "Enter VM admin password (azureuser): " VM_PASSWORD; echo ""
    [[ -n "$VM_PASSWORD" ]] || { echo "Password cannot be empty."; continue; }
    validate_password "$VM_PASSWORD" || { echo ""; continue; }
    read -s -p "Confirm password: " VM_PASSWORD_CONFIRM; echo ""
    [[ "$VM_PASSWORD" == "$VM_PASSWORD_CONFIRM" ]] && { echo "Password confirmed."; break; }
    echo "Passwords do not match. Try again."; echo ""
done

# ── Azure login ────────────────────────────────────────────────────────────────
echo ""
echo "Logging into Azure..."
az login --use-device-code
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || true
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || true

echo "Setting subscription: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"
echo "Active subscription: $(az account show --query name -o tsv)"

# ── Create resource group ──────────────────────────────────────────────────────
echo ""
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "eastus2" \
    --tags Purpose=DNS-Security-Lab Environment=Lab \
    --output none

# ── Deploy Bicep ───────────────────────────────────────────────────────────────
TEMPLATE_FILE="$SCRIPT_DIR/infra/main.bicep"
PARAMS_FILE="$SCRIPT_DIR/infra/main.bicepparam"

echo ""
echo "Deploying Bicep template..."
DEPLOY_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMS_FILE" \
    --parameters "vmAdminPassword=$VM_PASSWORD" \
    --output json)

# ── Print summary ──────────────────────────────────────────────────────────────
get_output() { echo "$DEPLOY_OUTPUT" | jq -r ".properties.outputs.$1.value"; }

echo ""
echo "=========================================="
echo "   DEPLOYMENT COMPLETED SUCCESSFULLY!     "
echo "=========================================="
echo ""
echo "Lab Environment Details:"
echo "  Resource Group      : $(get_output resourceGroupName)"
echo "  VM Name             : $(get_output vmName)"
echo "  VM Username         : $(get_output vmAdminUsername)"
echo "  Virtual Network     : $(get_output vnetName)"
echo "  DNS Security Policy : $(get_output dnsSecurityPolicyName)"
echo "  Log Analytics WS    : $(get_output logAnalyticsWorkspaceName)"
echo "  Blocked Domains     : $(get_output blockedDomains | jq -r 'join(", ")')"
echo ""
echo "VM Access (Serial Console):"
echo "  1. Go to https://portal.azure.com"
echo "  2. Navigate to Virtual Machines > $(get_output vmName)"
echo "  3. Click 'Serial console' under Help"
echo "  4. Login with username: $(get_output vmAdminUsername)"
echo ""
echo "Test DNS blocking from the VM:"
echo "  dig malicious.contoso.com   # should return blockpolicy.azuredns.invalid"
echo "  dig exploit.adatum.com      # should return blockpolicy.azuredns.invalid"
echo "  dig google.com              # should resolve normally"
echo ""


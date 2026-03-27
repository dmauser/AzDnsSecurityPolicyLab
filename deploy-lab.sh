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
    echo "Copy answers.json.template to answers.json."
    exit 1
fi

RESOURCE_GROUP_NAME=$(jq -r '.resourceGroupName' "$SCRIPT_DIR/answers.json")

if [[ -z "$RESOURCE_GROUP_NAME" || "$RESOURCE_GROUP_NAME" == "null" ]]; then
    echo "Error: resourceGroupName is required in answers.json."
    exit 1
fi

# ── Ensure Bicep CLI is available ─────────────────────────────────────────────
if ! command -v bicep &>/dev/null; then
    echo "Bicep CLI not found. Installing via Azure CLI..."
    az bicep install
    # az bicep installs to ~/.azure/bin — add to PATH for this session
    export PATH="$HOME/.azure/bin:$PATH"
    echo "Bicep CLI installed."
else
    echo "Bicep CLI found: $(bicep --version 2>&1 | head -1)"
fi

# ── Azure login (reuse existing session, login only if needed) ─────────────────
echo ""
echo "Checking for existing Azure session..."
mapfile -t SUB_IDS < <(az account list --query '[?state==`Enabled`].id' --output tsv 2>/dev/null)

if [[ ${#SUB_IDS[@]} -eq 0 ]]; then
    echo "No active session found. Logging into Azure..."
    az login --use-device-code
    az config set extension.dynamic_install_allow_preview=true 2>/dev/null || true
    az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || true
    mapfile -t SUB_IDS < <(az account list --query '[?state==`Enabled`].id' --output tsv)
fi

# ── Subscription selection ─────────────────────────────────────────────────────
mapfile -t SUB_NAMES < <(az account list --query '[?state==`Enabled`].name' --output tsv)

if [[ ${#SUB_IDS[@]} -eq 0 ]]; then
    echo "Error: No enabled Azure subscriptions found for the logged-in account."
    exit 1
fi

echo ""
echo "Available subscriptions:"
for i in "${!SUB_NAMES[@]}"; do
    printf "  [%d] %s\n      %s\n" $((i + 1)) "${SUB_NAMES[$i]}" "${SUB_IDS[$i]}"
done

SELECTED_INDEX=""
while true; do
    read -rp $'\nSelect subscription (1-'"${#SUB_IDS[@]}"'): ' SELECTED_INDEX
    if [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]] && \
       [[ "$SELECTED_INDEX" -ge 1 && "$SELECTED_INDEX" -le "${#SUB_IDS[@]}" ]]; then
        break
    fi
    echo "Invalid selection. Enter a number between 1 and ${#SUB_IDS[@]}."
done

SUBSCRIPTION_ID="${SUB_IDS[$((SELECTED_INDEX - 1))]}"
SUBSCRIPTION_NAME="${SUB_NAMES[$((SELECTED_INDEX - 1))]}"

az account set --subscription "$SUBSCRIPTION_ID"
echo "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# ── Resolve caller's Azure AD Object ID (for Key Vault access policy) ─────────
echo ""
echo "Resolving your Azure AD Object ID..."
ADMIN_OID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
if [[ -z "$ADMIN_OID" ]]; then
    echo "Could not auto-detect your Azure AD Object ID."
    echo "  Run manually: az ad signed-in-user show --query id -o tsv"
    read -rp "Azure AD Object ID: " ADMIN_OID
fi
echo "Key Vault access will be granted to OID: $ADMIN_OID"

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
# --only-show-errors suppresses informational stderr (e.g. Bicep progress lines)
set +e
DEPLOY_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMS_FILE" \
    --parameters "keyVaultAdminObjectId=$ADMIN_OID" \
    --only-show-errors \
    --output json 2>&1)
DEPLOY_EXIT=$?
set -e

if [[ $DEPLOY_EXIT -ne 0 ]]; then
    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT FAILED                "
    echo "=========================================="
    echo ""

    if echo "$DEPLOY_OUTPUT" | grep -qi "SkuNotAvailable"; then
        SKU=$(echo "$DEPLOY_OUTPUT" | grep -oP 'Standard_\w+' | head -1)
        LOC=$(echo "$DEPLOY_OUTPUT" | grep -oP "location '\K[^']+" | head -1)
        SKU=${SKU:-"the requested SKU"}
        LOC=${LOC:-"the selected region"}

        echo "VM SKU '$SKU' is not available in region '$LOC'."
        echo ""
        echo "How to fix:"
        echo "  Option 1: Change the region in infra/main.bicepparam (e.g. westus2, westeurope)"
        echo "  Option 2: Change vmSize in infra/main.bicepparam (e.g. Standard_B2s, Standard_DS1_v2)"
        echo ""
        echo "Check available SKUs for a region:"
        echo "  az vm list-skus --location $LOC --size Standard_B --output table"
        echo ""
    elif echo "$DEPLOY_OUTPUT" | grep -qi "BastionHostSkuNotAvailable\|Bastion.*not available"; then
        echo "Azure Bastion Developer SKU is not available in this region."
        echo ""
        echo "How to fix:"
        echo "  Change 'location' in infra/main.bicepparam to a supported region."
        echo "  Supported regions include: eastus, westus, eastus2, westeurope, northeurope"
        echo "  Full list: https://aka.ms/bastionsku"
        echo ""
    else
        echo "Error details:"
        echo "$DEPLOY_OUTPUT"
        echo ""
    fi

    echo "The resource group '$RESOURCE_GROUP_NAME' may contain partial resources."
    echo "To clean up: ./remove-lab.sh  (or: az group delete -n $RESOURCE_GROUP_NAME --no-wait)"
    echo ""
    exit 1
fi

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
echo "  Azure Bastion       : $(get_output bastionName)"
echo "  DNS Security Policy : $(get_output dnsSecurityPolicyName)"
echo "  Log Analytics WS    : $(get_output logAnalyticsWorkspaceName)"
echo "  Blocked Domains     : $(get_output blockedDomains | jq -r 'join(", ")')"
echo "  Key Vault           : $(get_output keyVaultName)"
echo ""
echo "Retrieve VM Password from Key Vault:"
echo "  az keyvault secret show --vault-name '$(get_output keyVaultName)' --name 'vm-admin-password' --query value -o tsv"
echo ""
echo "VM Access via Azure Bastion (Developer SKU):"
echo "  1. Go to https://portal.azure.com"
echo "  2. Navigate to Virtual Machines > $(get_output vmName)"
echo "  3. Click 'Connect' > 'Connect via Bastion'"
echo "  4. Authentication Type: 'Password' (NOT 'Password from Azure Key Vault')"
echo "  5. Username: $(get_output vmAdminUsername)"
echo "  6. Paste the password retrieved from Key Vault above"
echo ""
echo "  NOTE: 'Password from Azure Key Vault' requires Bastion Basic/Standard (~\$139/mo)."
echo "        Developer SKU is free — just retrieve and paste the password manually."
echo ""
echo "Test DNS blocking from the VM:"
echo "  dig malicious.contoso.com   # should return blockpolicy.azuredns.invalid"
echo "  dig exploit.adatum.com      # should return blockpolicy.azuredns.invalid"
echo "  dig google.com              # should resolve normally"
echo ""


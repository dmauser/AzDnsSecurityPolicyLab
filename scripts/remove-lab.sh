#!/bin/bash

# Azure DNS Security Policy Lab Removal Script
# This script removes the entire DNS security policy lab environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo " Azure DNS Security Policy Lab Removal"
echo "=========================================="

# ── Read configuration ─────────────────────────────────────────────────────────
if [[ ! -f "$REPO_ROOT/answers.json" ]]; then
    echo "Error: answers.json not found in repo root."
    exit 1
fi

RESOURCE_GROUP_NAME=$(jq -r '.resourceGroupName' "$REPO_ROOT/answers.json")

if [[ -z "$RESOURCE_GROUP_NAME" || "$RESOURCE_GROUP_NAME" == "null" ]]; then
    echo "Error: resourceGroupName is required in answers.json"
    exit 1
fi

# ── Azure login (reuse existing session, login only if needed) ─────────────────
echo ""
echo "Checking for existing Azure session..."
SUB_IDS=()
while IFS= read -r line; do SUB_IDS+=("$line"); done < <(az account list --query '[?state==`Enabled`].id' --output tsv 2>/dev/null)

if [[ ${#SUB_IDS[@]} -eq 0 ]]; then
    echo "No active session found. Logging into Azure..."
    az login --use-device-code
    SUB_IDS=()
    while IFS= read -r line; do SUB_IDS+=("$line"); done < <(az account list --query '[?state==`Enabled`].id' --output tsv)
fi

# ── Subscription selection ─────────────────────────────────────────────────────
SUB_NAMES=()
while IFS= read -r line; do SUB_NAMES+=("$line"); done < <(az account list --query '[?state==`Enabled`].name' --output tsv)

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

# ── Check resource group exists ────────────────────────────────────────────────
echo ""
if ! az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP_NAME' does not exist. Nothing to remove."
    exit 0
fi

# ── Confirm deletion ───────────────────────────────────────────────────────────
echo ""
echo "WARNING: This will permanently delete resource group '$RESOURCE_GROUP_NAME'"
echo "         and ALL resources inside it."
echo ""
read -rp "Type the resource group name to confirm deletion: " CONFIRM

if [[ "$CONFIRM" != "$RESOURCE_GROUP_NAME" ]]; then
    echo "Confirmation did not match. Deletion cancelled."
    exit 0
fi

# ── Discover Key Vault(s) to purge after RG deletion ─────────────────────────
VAULT_NAMES=()
while IFS= read -r line; do VAULT_NAMES+=("$line"); done < <(az keyvault list --resource-group "$RESOURCE_GROUP_NAME" --query '[].name' --output tsv 2>/dev/null)

# ── Delete resource group (no-wait) ───────────────────────────────────────────
echo ""
echo "Deleting resource group '$RESOURCE_GROUP_NAME'..."

az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

echo "Resource group deletion initiated (running in background)."

# ── Purge soft-deleted Key Vaults ─────────────────────────────────────────────
for VAULT_NAME in "${VAULT_NAMES[@]}"; do
    echo "Purging soft-deleted Key Vault '$VAULT_NAME'..."
    VAULT_LOCATION=$(az keyvault show-deleted --name "$VAULT_NAME" --query 'properties.location' --output tsv 2>/dev/null || true)
    if [[ -n "$VAULT_LOCATION" ]]; then
        if az keyvault purge --name "$VAULT_NAME" --location "$VAULT_LOCATION" 2>/dev/null; then
            echo "Key Vault '$VAULT_NAME' purged."
        else
            echo "Could not purge Key Vault '$VAULT_NAME'."
        fi
    fi
done

echo ""
echo "Lab removal initiated. The resource group deletion continues in the background."
echo "Check status with: az group show --name '$RESOURCE_GROUP_NAME'"

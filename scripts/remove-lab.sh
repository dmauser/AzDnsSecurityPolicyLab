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
echo "Checking if resource group exists: $RESOURCE_GROUP_NAME"
if ! az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP_NAME' does not exist. Nothing to remove."
    exit 0
fi

# ── Confirm deletion ───────────────────────────────────────────────────────────
echo ""
echo "WARNING: This will permanently delete the following resource group and ALL its contents:"
echo "  Resource Group : $RESOURCE_GROUP_NAME"
echo "  Subscription   : $SUBSCRIPTION_NAME"
echo ""
read -rp "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# ── List and delete ────────────────────────────────────────────────────────────
echo ""
echo "Resources to be deleted:"
echo "------------------------"
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table

echo ""
echo "Deleting resource group: $RESOURCE_GROUP_NAME"
echo "This may take several minutes..."

az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

echo ""
echo "Deletion initiated in the background."
echo "Monitor progress in the Azure Portal under Resource Groups."
echo ""

echo ""
echo "=========================================="
echo "REMOVAL INITIATED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "The resource group '$RESOURCE_GROUP_NAME' deletion has been initiated."
echo "This process will continue in the background and may take several minutes to complete."
echo ""
echo "You can check the deletion status with:"
echo "az group show --name '$RESOURCE_GROUP_NAME'"
echo ""
echo "When the resource group no longer exists, the deletion is complete."
echo ""

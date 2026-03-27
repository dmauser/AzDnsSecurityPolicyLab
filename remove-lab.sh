#!/bin/bash

# Azure DNS Security Policy Lab Removal Script
# This script removes the entire DNS security policy lab environment

set -e  # Exit on any error

echo "=========================================="
echo "Azure DNS Security Policy Lab Removal"
echo "=========================================="

# Check if answers.json exists
if [[ ! -f "answers.json" ]]; then
    echo "Error: answers.json file not found. Please ensure it exists with the lab configuration."
    exit 1
fi

# Read configuration from answers.json
RESOURCE_GROUP_NAME=$(jq -r '.resourceGroupName' answers.json)

# Validate required fields
if [[ -z "$RESOURCE_GROUP_NAME" || "$RESOURCE_GROUP_NAME" == "null" ]]; then
    echo "Error: resourceGroupName is required in answers.json"
    exit 1
fi

# Login to Azure with device code
echo ""
echo "Logging into Azure..."
az login --use-device-code

# Subscription selection
echo ""
echo "Available subscriptions:"

mapfile -t SUB_NAMES < <(az account list --query '[?state==`Enabled`].name' --output tsv)
mapfile -t SUB_IDS   < <(az account list --query '[?state==`Enabled`].id'   --output tsv)

if [[ ${#SUB_IDS[@]} -eq 0 ]]; then
    echo "Error: No enabled Azure subscriptions found for the logged-in account."
    exit 1
fi

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

# Check if resource group exists
echo ""
echo "Checking if resource group exists: $RESOURCE_GROUP_NAME"
if ! az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP_NAME' does not exist. Nothing to remove."
    exit 0
fi

# Confirm deletion
echo ""
echo "WARNING: This will permanently delete the following resource group and ALL its contents:"
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Subscription: $(az account show --query name -o tsv)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# List resources in the resource group before deletion
echo ""
echo "Resources to be deleted:"
echo "------------------------"
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table

echo ""
echo "Deleting resource group: $RESOURCE_GROUP_NAME"
echo "This may take several minutes..."

# Delete the resource group and all its resources
az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

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

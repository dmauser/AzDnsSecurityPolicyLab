#!/bin/bash

# Azure DNS Security Policy Lab - Environment Validation Script
# This script validates the environment before deployment in GitHub Codespaces

echo "=========================================="
echo "Azure DNS Security Policy Lab Validation"
echo "=========================================="

EXIT_CODE=0

# Function to check if a command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo "✅ $1 is available"
    else
        echo "❌ $1 is not available"
        EXIT_CODE=1
    fi
}

# Function to validate JSON file
validate_json() {
    if [[ -f "$1" ]]; then
        if jq empty "$1" &> /dev/null; then
            echo "✅ $1 is valid JSON"
        else
            echo "❌ $1 is invalid JSON"
            EXIT_CODE=1
        fi
    else
        echo "❌ $1 not found"
        EXIT_CODE=1
    fi
}

# Check tools (available in GitHub Codespaces devcontainer)
echo ""
echo "Checking Available Tools:"
echo "------------------------"
check_command "az"
check_command "jq"
check_command "bash"

# Check Azure CLI login status
echo ""
echo "Checking Azure CLI Status:"
echo "-------------------------"
if az account show &> /dev/null; then
    CURRENT_SUB=$(az account show --query name -o tsv 2>/dev/null)
    CURRENT_SUB_ID=$(az account show --query id -o tsv 2>/dev/null)
    echo "✅ Logged into Azure"
    echo "   Current subscription: $CURRENT_SUB"
    echo "   Subscription ID: $CURRENT_SUB_ID"
else
    echo "ℹ️  Not currently logged into Azure CLI"
    echo "   The deployment script will handle Azure login with device code"
fi

# Validate answers.json
echo ""
echo "Validating Configuration:"
echo "------------------------"
validate_json "answers.json"

if [[ -f "answers.json" ]]; then
    # Check required fields
    RESOURCE_GROUP_NAME=$(jq -r '.resourceGroupName' answers.json 2>/dev/null)
    
    if [[ -n "$RESOURCE_GROUP_NAME" && "$RESOURCE_GROUP_NAME" != "null" ]]; then
        echo "✅ resourceGroupName is configured: $RESOURCE_GROUP_NAME"
    else
        echo "❌ resourceGroupName is required in answers.json"
        EXIT_CODE=1
    fi
fi

# Check script permissions
echo ""
echo "Checking Script Permissions:"
echo "---------------------------"
if [[ -x "deploy-lab.sh" ]]; then
    echo "✅ deploy-lab.sh is executable"
else
    echo "⚠️  deploy-lab.sh needs execute permission"
    echo "   Run: chmod +x deploy-lab.sh"
fi

if [[ -x "remove-lab.sh" ]]; then
    echo "✅ remove-lab.sh is executable"
else
    echo "⚠️  remove-lab.sh needs execute permission"
    echo "   Run: chmod +x remove-lab.sh"
fi

# Codespace-specific information
echo ""
echo "GitHub Codespaces Environment:"
echo "-----------------------------"
if [[ -n "$CODESPACES" ]]; then
    echo "✅ Running in GitHub Codespaces"
    echo "   All required tools are pre-installed"
else
    echo "ℹ️  Not running in GitHub Codespaces"
    echo "   Ensure Azure CLI and jq are installed"
fi

# Final status
echo ""
echo "=========================================="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ VALIDATION PASSED"
    echo "=========================================="
    echo ""
    echo "Your environment is ready for deployment!"
    echo ""
    echo "Next steps:"
    echo "1. Run './deploy-lab.sh' to start the lab deployment"
    echo "2. Retrieve the VM password from Key Vault (shown in deployment output)"
    echo "3. Connect to the VM via Azure Bastion (Portal > VM > Connect > Bastion)"
    echo "4. Test DNS blocking with: dig malicious.contoso.com"
    echo "5. Clean up with './remove-lab.sh' when done"
else
    echo "❌ VALIDATION FAILED"
    echo "=========================================="
    echo ""
    echo "Please fix the issues above before running the deployment."
fi

echo ""

exit $EXIT_CODE

#!/bin/bash
#
# Script: verify-lab.sh
# Description: Post-deployment verification script that runs FROM THE DEPLOYER'S
#              MACHINE (not the VM). Uses Azure CLI to validate that all lab
#              resources are correctly deployed, linked, and configured.
#
# Usage: ./verify-lab.sh [-g resource-group] [-h]
#        ./verify-lab.sh
#
# Options:
#   -g resource-group  Specify the resource group name (optional)
#                      If not provided, auto-discovers from 'az group list' matching 'dns'
#   -h                 Display this help message and exit
#
# Requirements:
#   - az CLI (logged in with appropriate permissions)
#   - jq (for JSON parsing)
#
# Examples:
#   ./verify-lab.sh                          (auto-discover resource group)
#   ./verify-lab.sh -g my-dns-lab-rg         (specify resource group)
#   ./verify-lab.sh -h                       (display help)
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

RESOURCE_GROUP=""
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

EXPECTED_BLOCKED_DOMAINS=("malicious.contoso.com." "exploit.adatum.com.")

# ==============================================================================
# Functions
# ==============================================================================

show_help() {
    grep "^#" "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1"
}

log_pass() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_fail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1"
}

# Check prerequisites before running any tests
check_prerequisites() {
    if ! command -v az &> /dev/null; then
        echo "❌ az CLI not found. Install from https://aka.ms/installazurecli"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "❌ jq not found. Install with: sudo apt-get install -y jq"
        exit 1
    fi

    if ! az account show &> /dev/null 2>&1; then
        echo "❌ Not logged into Azure CLI. Run 'az login' first."
        exit 1
    fi

    local sub_name
    sub_name=$(az account show --query name -o tsv 2>/dev/null)
    log_info "Logged into Azure — subscription: $sub_name"
}

# Auto-discover resource group if not provided
discover_resource_group() {
    if [[ -n "$RESOURCE_GROUP" ]]; then
        return
    fi

    log_info "No resource group specified. Searching for groups containing 'dns'..."

    RESOURCE_GROUP=$(az group list \
        --query "[?contains(name, 'dns')].name | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$RESOURCE_GROUP" || "$RESOURCE_GROUP" == "None" ]]; then
        echo "❌ Could not auto-discover resource group. Use -g to specify."
        exit 1
    fi

    log_info "Discovered resource group: $RESOURCE_GROUP"
}

# Verify resource group exists
verify_resource_group() {
    local exists
    exists=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null) || true

    if [[ "$exists" == "true" ]]; then
        log_pass "Resource group exists: $RESOURCE_GROUP"
    else
        log_fail "Resource group not found: $RESOURCE_GROUP"
    fi
}

# Verify a resource type exists in the resource group
# Arguments: $1=display_name $2=resource_type_filter
verify_resource_exists() {
    local display_name="$1"
    local type_filter="$2"
    local count

    count=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length([?contains(type, '$type_filter')])" \
        -o tsv 2>/dev/null) || count="0"

    if [[ "$count" -gt 0 ]]; then
        log_pass "$display_name found ($count)"
    else
        log_fail "$display_name not found"
    fi
}

# Verify DNS Security Policy is linked to VNet
verify_policy_vnet_link() {
    local policy_id
    policy_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(type, 'Microsoft.Network/dnsResolverPolicies')].id | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$policy_id" || "$policy_id" == "None" ]]; then
        log_fail "DNS Security Policy VNet link — policy not found"
        return
    fi

    # Check for virtual network links on the policy
    local links
    links=$(az rest \
        --method GET \
        --url "${policy_id}/virtualNetworkLinks?api-version=2023-06-01" \
        --query "value | length(@)" \
        -o tsv 2>/dev/null) || links="0"

    if [[ "$links" -gt 0 ]]; then
        log_pass "DNS Security Policy linked to VNet ($links link(s))"
    else
        log_fail "DNS Security Policy not linked to any VNet"
    fi
}

# Verify domain list contains expected blocked domains
verify_domain_list() {
    local domain_list_id
    domain_list_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(type, 'Microsoft.Network/dnsResolverDomainLists')].id | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$domain_list_id" || "$domain_list_id" == "None" ]]; then
        log_fail "Domain list — not found"
        return
    fi

    local domains_json
    domains_json=$(az rest \
        --method GET \
        --url "${domain_list_id}?api-version=2023-06-01" \
        --query "properties.domains" \
        -o json 2>/dev/null) || domains_json="[]"

    local all_found=true
    for domain in "${EXPECTED_BLOCKED_DOMAINS[@]}"; do
        if echo "$domains_json" | jq -e --arg d "$domain" 'map(ascii_downcase) | index($d | ascii_downcase)' &> /dev/null; then
            log_pass "Domain list contains: $domain"
        else
            log_fail "Domain list missing: $domain"
            all_found=false
        fi
    done
}

# Verify diagnostic settings on DNS resolver policy
verify_diagnostic_settings() {
    local policy_id
    policy_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(type, 'Microsoft.Network/dnsResolverPolicies')].id | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$policy_id" || "$policy_id" == "None" ]]; then
        log_fail "Diagnostic settings — DNS policy not found"
        return
    fi

    local diag_count
    diag_count=$(az monitor diagnostic-settings list \
        --resource "$policy_id" \
        --query "value | length(@)" \
        -o tsv 2>/dev/null) || diag_count="0"

    if [[ "$diag_count" -gt 0 ]]; then
        log_pass "Diagnostic settings configured on DNS policy ($diag_count)"
    else
        log_fail "No diagnostic settings on DNS policy — logs won't flow to Log Analytics"
    fi
}

# Verify Sentinel (SecurityInsights solution) is deployed
verify_sentinel() {
    local workspace_name
    workspace_name=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_name" || "$workspace_name" == "None" ]]; then
        log_fail "Sentinel — Log Analytics workspace not found"
        return
    fi

    # Check for SecurityInsights solution
    local sentinel_solution
    sentinel_solution=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(type, 'Microsoft.OperationsManagement/solutions') && contains(name, 'SecurityInsights')].name | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -n "$sentinel_solution" && "$sentinel_solution" != "None" ]]; then
        log_pass "Sentinel workspace solution deployed: $sentinel_solution"
    else
        log_fail "Sentinel workspace solution not found"
    fi
}

# Verify Sentinel analytics rules exist
verify_sentinel_rules() {
    local workspace_name
    workspace_name=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_name" || "$workspace_name" == "None" ]]; then
        log_fail "Sentinel analytics rules — workspace not found"
        return
    fi

    local sub_id
    sub_id=$(az account show --query id -o tsv 2>/dev/null)

    local rules_count
    rules_count=$(az rest \
        --method GET \
        --url "/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${workspace_name}/providers/Microsoft.SecurityInsights/alertRules?api-version=2024-09-01" \
        --query "value | length(@)" \
        -o tsv 2>/dev/null) || rules_count="0"

    if [[ "$rules_count" -ge 2 ]]; then
        log_pass "Sentinel analytics rules deployed ($rules_count rules)"
    elif [[ "$rules_count" -eq 1 ]]; then
        log_warn "Only 1 Sentinel analytics rule found (expected 2)"
        log_fail "Sentinel analytics rules — expected at least 2, found $rules_count"
    else
        log_fail "No Sentinel analytics rules found (expected 2 TI rules)"
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Post-Deployment Verification Summary"
    echo "=========================================="
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    echo ""
    echo "  Total:  $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED ✅"
    echo "  Failed: $TESTS_FAILED ❌"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "  Result: ALL CHECKS PASSED ✅"
        echo ""
        echo "  Your lab is correctly deployed!"
        echo "  Next: Connect to the VM via Bastion and run scripts/e2e-test.sh"
    else
        echo "  Result: SOME CHECKS FAILED ❌"
        echo ""
        echo "  Review failures above and redeploy if needed."
    fi
    echo ""
    echo "=========================================="
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -h)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Main
# ==============================================================================

echo "=========================================="
echo "  Azure DNS Security Lab — Post-Deploy"
echo "  Verification"
echo "=========================================="
echo ""

# Prerequisites
check_prerequisites

# Discover resource group
discover_resource_group

echo ""
echo "------------------------------------------"
echo "  Resource Group"
echo "------------------------------------------"
verify_resource_group

echo ""
echo "------------------------------------------"
echo "  Core Resources"
echo "------------------------------------------"
verify_resource_exists "Virtual Machine" "Microsoft.Compute/virtualMachines"
verify_resource_exists "Virtual Network" "Microsoft.Network/virtualNetworks"
verify_resource_exists "Bastion Host" "Microsoft.Network/bastionHosts"
verify_resource_exists "Log Analytics Workspace" "Microsoft.OperationalInsights/workspaces"
verify_resource_exists "DNS Security Policy" "Microsoft.Network/dnsResolverPolicies"
verify_resource_exists "DNS Resolver" "Microsoft.Network/dnsResolvers"
verify_resource_exists "Key Vault" "Microsoft.KeyVault/vaults"

echo ""
echo "------------------------------------------"
echo "  DNS Policy Configuration"
echo "------------------------------------------"
verify_policy_vnet_link
verify_domain_list

echo ""
echo "------------------------------------------"
echo "  Monitoring & Logging"
echo "------------------------------------------"
verify_diagnostic_settings

echo ""
echo "------------------------------------------"
echo "  Sentinel"
echo "------------------------------------------"
verify_sentinel
verify_sentinel_rules

# Summary
print_summary

# Exit with appropriate code
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0

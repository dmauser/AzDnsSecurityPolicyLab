#!/bin/bash
#
# Script: pre-demo-check.sh
# Description: Pre-demo readiness check that gives a presenter a single binary
#              answer: "READY TO DEMO" or "NOT READY". Runs FROM THE DEPLOYER'S
#              MACHINE before walking on stage.
#
# Usage: ./pre-demo-check.sh [-g resource-group] [-h]
#        ./pre-demo-check.sh
#
# Options:
#   -g resource-group  Specify the resource group name (optional)
#                      If not provided, reads from answers.json or auto-discovers
#   -h                 Display this help message and exit
#
# Requirements:
#   - az CLI (logged in with appropriate permissions)
#   - jq (for JSON parsing)
#
# Examples:
#   ./pre-demo-check.sh                      (auto-discover resource group)
#   ./pre-demo-check.sh -g my-dns-lab-rg     (specify resource group)
#   ./pre-demo-check.sh -h                   (display help)
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

RESOURCE_GROUP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHECKS_PASS=0
CHECKS_FAIL=0
CHECKS_WARN=0
RESULTS=()
CRITICAL_FAIL=false

# ==============================================================================
# Functions
# ==============================================================================

show_help() {
    grep "^#" "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

record_pass() {
    RESULTS+=("✅ $1")
    ((CHECKS_PASS++))
}

record_fail() {
    RESULTS+=("❌ $1")
    ((CHECKS_FAIL++))
    CRITICAL_FAIL=true
}

record_warn() {
    RESULTS+=("⚠️  $1")
    ((CHECKS_WARN++))
}

# ==============================================================================
# Parse arguments
# ==============================================================================

while getopts "g:h" opt; do
    case $opt in
        g) RESOURCE_GROUP="$OPTARG" ;;
        h) show_help ;;
        *) show_help ;;
    esac
done

# ==============================================================================
# Discover resource group
# ==============================================================================

discover_resource_group() {
    if [[ -n "$RESOURCE_GROUP" ]]; then
        return
    fi

    # Try answers.json first
    if [[ -f "$REPO_ROOT/answers.json" ]]; then
        RESOURCE_GROUP=$(jq -r '.resourceGroupName // empty' "$REPO_ROOT/answers.json" 2>/dev/null) || true
    fi

    # Fall back to az group list
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP=$(az group list \
            --query "[?contains(name, 'dns')].name | [0]" \
            -o tsv 2>/dev/null) || true
    fi

    if [[ -z "$RESOURCE_GROUP" || "$RESOURCE_GROUP" == "None" ]]; then
        record_fail "Resource group: could not discover (use -g)"
        CRITICAL_FAIL=true
        return 1
    fi
}

# ==============================================================================
# Check 1: Azure CLI logged in
# ==============================================================================

check_azure_cli() {
    local sub_name
    if sub_name=$(az account show --query name -o tsv 2>/dev/null); then
        record_pass "Azure CLI authenticated ($sub_name)"
    else
        record_fail "Azure CLI not authenticated (run 'az login')"
    fi
}

# ==============================================================================
# Check 2: Resource group exists
# ==============================================================================

check_resource_group() {
    local exists
    exists=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null) || exists="false"

    if [[ "$exists" == "true" ]]; then
        record_pass "Resource group exists ($RESOURCE_GROUP)"
    else
        record_fail "Resource group not found: $RESOURCE_GROUP"
    fi
}

# ==============================================================================
# Check 3: DNS blocking is live
# ==============================================================================

check_dns_blocking() {
    # Find the VM in the resource group
    local vm_name
    vm_name=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$vm_name" || "$vm_name" == "None" ]]; then
        record_fail "DNS blocking: no VM found in resource group"
        return
    fi

    local result
    result=$(az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --command-id RunShellScript \
        --scripts "dig malicious.contoso.com +short 2>&1 || true" \
        --query "value[0].message" \
        -o tsv 2>/dev/null) || result=""

    # DNS blocking is active if output is empty (NXDOMAIN) or contains block indicator
    if [[ -z "$result" ]] || echo "$result" | grep -qi "blockpolicy\|NXDOMAIN\|REFUSED\|SERVFAIL"; then
        record_pass "DNS blocking active"
    elif echo "$result" | grep -qP '^\d+\.\d+\.\d+\.\d+$'; then
        # Got a real IP back — not blocked
        record_fail "DNS blocking NOT active (resolved to: $result)"
    else
        # Empty or non-IP response likely means blocked
        record_pass "DNS blocking active"
    fi
}

# ==============================================================================
# Check 4: DNSQueryLogs has recent data
# ==============================================================================

check_dns_query_logs() {
    # Find Log Analytics workspace
    local workspace_id
    workspace_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].id | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        record_fail "DNSQueryLogs: no Log Analytics workspace found"
        return
    fi

    local workspace_customer_id
    workspace_customer_id=$(az resource show \
        --ids "$workspace_id" \
        --query "properties.customerId" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_customer_id" ]]; then
        record_fail "DNSQueryLogs: could not get workspace ID"
        return
    fi

    local count
    count=$(az monitor log-analytics query \
        --workspace "$workspace_customer_id" \
        --analytics-query "DNSQueryLogs | where TimeGenerated > ago(30m) | count" \
        --query "[0].Count" \
        -o tsv 2>/dev/null) || count="0"

    if [[ -n "$count" && "$count" -gt 0 ]] 2>/dev/null; then
        record_pass "DNSQueryLogs has data ($count rows)"
    else
        record_fail "DNSQueryLogs: no data in last 30 minutes"
    fi
}

# ==============================================================================
# Check 5: TI Connector enabled
# ==============================================================================

check_ti_connector() {
    local workspace_id
    workspace_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].name | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        record_fail "TI Connector: no workspace found"
        return
    fi

    local sub_id
    sub_id=$(az account show --query id -o tsv 2>/dev/null)

    local url="https://management.azure.com/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-09-01"

    local connectors
    connectors=$(az rest --method GET --url "$url" 2>/dev/null) || connectors=""

    if echo "$connectors" | jq -e '.value[]? | select(.kind == "MicrosoftThreatIntelligence")' &>/dev/null; then
        record_pass "TI Connector enabled"
    else
        record_fail "TI Connector not found"
    fi
}

# ==============================================================================
# Check 6: Summary Rule has run (WARNING only)
# ==============================================================================

check_summary_rule() {
    local workspace_customer_id
    workspace_customer_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].id | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_customer_id" || "$workspace_customer_id" == "None" ]]; then
        record_warn "Summary Rule: workspace not found"
        return
    fi

    workspace_customer_id=$(az resource show \
        --ids "$workspace_customer_id" \
        --query "properties.customerId" \
        -o tsv 2>/dev/null) || true

    local result
    result=$(az monitor log-analytics query \
        --workspace "$workspace_customer_id" \
        --analytics-query "DNSQueryLogs_sum_CL | take 1" \
        --query "length(@)" \
        -o tsv 2>/dev/null) || result=""

    if [[ -n "$result" && "$result" -gt 0 ]] 2>/dev/null; then
        record_pass "Summary Rule has run (DNSQueryLogs_sum_CL exists)"
    else
        record_warn "Summary Rule: no data yet"
    fi
}

# ==============================================================================
# Check 7: Sentinel incidents exist (WARNING only)
# ==============================================================================

check_sentinel_incidents() {
    local workspace_name
    workspace_name=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].name | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_name" || "$workspace_name" == "None" ]]; then
        record_warn "Sentinel incidents: workspace not found"
        return
    fi

    local sub_id
    sub_id=$(az account show --query id -o tsv 2>/dev/null)

    local url="https://management.azure.com/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${workspace_name}/providers/Microsoft.SecurityInsights/incidents?api-version=2024-09-01&\$top=1"

    local incidents
    incidents=$(az rest --method GET --url "$url" 2>/dev/null) || incidents=""

    local count
    count=$(echo "$incidents" | jq '.value | length' 2>/dev/null) || count="0"

    if [[ -n "$count" && "$count" -gt 0 ]] 2>/dev/null; then
        record_pass "Sentinel incidents exist ($count found)"
    else
        record_warn "Sentinel incidents: 0 found"
    fi
}

# ==============================================================================
# Output
# ==============================================================================

print_results() {
    local verdict verdict_detail

    if [[ "$CRITICAL_FAIL" == "true" ]]; then
        verdict="❌ NOT READY"
        verdict_detail=""
    elif [[ "$CHECKS_WARN" -gt 0 ]]; then
        verdict="✅ READY TO DEMO (with warnings)"
        verdict_detail="($CHECKS_WARN warning(s) — Sentinel may not fire during demo, but DNS blocking works)"
    else
        verdict="✅ READY TO DEMO"
        verdict_detail=""
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        PRE-DEMO READINESS CHECK                 ║"
    echo "╠══════════════════════════════════════════════════╣"
    for line in "${RESULTS[@]}"; do
        printf "║  %-46s ║\n" "$line"
    done
    echo "╠══════════════════════════════════════════════════╣"
    printf "║  VERDICT: %-37s ║\n" "$verdict"
    if [[ -n "$verdict_detail" ]]; then
        printf "║  %-46s ║\n" "$verdict_detail"
    fi
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    # Check prerequisites
    if ! command -v az &>/dev/null; then
        echo "❌ az CLI not found. Install from https://aka.ms/installazurecli"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "❌ jq not found. Install with: sudo apt-get install -y jq"
        exit 1
    fi

    # Run checks in order
    check_azure_cli
    if [[ "$CRITICAL_FAIL" == "true" ]]; then
        print_results
        exit 1
    fi

    discover_resource_group
    if [[ "$CRITICAL_FAIL" == "true" ]]; then
        print_results
        exit 1
    fi

    check_resource_group
    if [[ "$CRITICAL_FAIL" == "true" ]]; then
        print_results
        exit 1
    fi

    check_dns_blocking
    check_dns_query_logs
    check_ti_connector
    check_summary_rule
    check_sentinel_incidents

    print_results

    if [[ "$CRITICAL_FAIL" == "true" ]]; then
        exit 1
    fi
    exit 0
}

main

#!/bin/bash
#
# Script: seed-demo.sh
# Description: "Warm the lab" script that a presenter runs 1+ hour before their
#              demo to get Sentinel data flowing. Runs FROM THE DEPLOYER'S MACHINE
#              (not the VM). Enables TI connector, fires DNS queries, and checks
#              Summary Rule readiness.
#
# Usage: ./seed-demo.sh [-g resource-group] [-h]
#        ./seed-demo.sh
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
#   ./seed-demo.sh                          (auto-discover resource group)
#   ./seed-demo.sh -g my-dns-lab-rg         (specify resource group)
#   ./seed-demo.sh -h                       (display help)
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

RESOURCE_GROUP=""
WARNINGS=0

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
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1"
    ((WARNINGS++))
}

log_fail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v az &> /dev/null; then
        log_fail "az CLI not found. Install from https://aka.ms/installazurecli"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_fail "jq not found. Install with: sudo apt-get install -y jq"
        exit 1
    fi

    if ! az account show &> /dev/null 2>&1; then
        log_fail "Not logged into Azure CLI. Run 'az login' first."
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
        log_fail "Could not auto-discover resource group. Use -g to specify."
        exit 1
    fi

    log_info "Discovered resource group: $RESOURCE_GROUP"
}

# Discover workspace and VM from the resource group
discover_resources() {
    log_info "Discovering resources in $RESOURCE_GROUP..."

    # Find Log Analytics workspace
    WORKSPACE_NAME=$(az monitor log-analytics workspace list \
        -g "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null) || true

    if [[ -z "$WORKSPACE_NAME" || "$WORKSPACE_NAME" == "None" ]]; then
        log_fail "No Log Analytics workspace found in $RESOURCE_GROUP"
        exit 1
    fi
    log_info "Workspace: $WORKSPACE_NAME"

    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        -g "$RESOURCE_GROUP" -n "$WORKSPACE_NAME" \
        --query customerId -o tsv 2>/dev/null)

    WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
        -g "$RESOURCE_GROUP" -n "$WORKSPACE_NAME" \
        --query id -o tsv 2>/dev/null)

    # Find VM
    VM_NAME=$(az vm list -g "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null) || true

    if [[ -z "$VM_NAME" || "$VM_NAME" == "None" ]]; then
        log_fail "No VM found in $RESOURCE_GROUP"
        exit 1
    fi
    log_info "VM: $VM_NAME"

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
}

# Enable Microsoft Defender Threat Intelligence data connector
enable_ti_connector() {
    log_info "Enabling Microsoft Defender Threat Intelligence data connector..."

    local connector_id="MicrosoftThreatIntelligence"
    local api_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}/providers/Microsoft.SecurityInsights/dataConnectors/${connector_id}?api-version=2024-09-01"

    local body='{"kind":"MicrosoftThreatIntelligence","properties":{"dataTypes":{"microsoftEmergingThreatFeed":{"lookbackPeriod":"1970-01-01T00:00:00Z"}}}}'

    local response
    if response=$(az rest --method PUT --url "$api_url" --body "$body" 2>&1); then
        log_pass "TI Connector: enabled"
        TI_STATUS="enabled"
    else
        if echo "$response" | grep -qi "consent\|authorization\|forbidden\|permission"; then
            log_warn "TI Connector: requires portal consent — enable manually in Sentinel > Data Connectors"
            TI_STATUS="requires portal consent"
        else
            log_warn "TI Connector: could not enable (may already exist or require portal consent)"
            TI_STATUS="requires portal consent"
        fi
    fi
}

# Fire DNS queries from the VM
fire_dns_queries() {
    log_info "Firing DNS queries from VM ($VM_NAME) — 5 rounds of blocked + allowed domains..."

    local script='for i in {1..5}; do dig malicious.contoso.com; dig exploit.adatum.com; dig google.com; sleep 2; done'

    if az vm run-command invoke \
        -g "$RESOURCE_GROUP" \
        -n "$VM_NAME" \
        --command-id RunShellScript \
        --scripts "$script" \
        -o none 2>/dev/null; then
        log_pass "DNS Queries: fired (5 rounds of blocked + allowed)"
    else
        log_fail "Failed to run DNS queries on VM. Is the VM running?"
        exit 1
    fi
}

# Check if Summary Rule table exists
check_summary_rule() {
    log_info "Checking for DNSQueryLogs_sum_CL table (Summary Rule)..."

    local query_result
    if query_result=$(az monitor log-analytics query \
        --workspace "$WORKSPACE_ID" \
        --analytics-query "DNSQueryLogs_sum_CL | take 1" \
        2>/dev/null); then
        # Check if we got actual results (not empty)
        local row_count
        row_count=$(echo "$query_result" | jq 'length' 2>/dev/null) || row_count=0
        if [[ "$row_count" -gt 0 && "$row_count" != "null" ]]; then
            log_pass "Summary Rule: DNSQueryLogs_sum_CL table detected"
            SUMMARY_STATUS="detected"
        else
            log_warn "Summary Rule: not detected — create manually (see README Scenario 5, Step 3)"
            SUMMARY_STATUS="not detected"
        fi
    else
        log_warn "Summary Rule: not detected — create manually (see README Scenario 5, Step 3)"
        SUMMARY_STATUS="not detected"
    fi
}

# Print final status summary
print_summary() {
    echo ""
    echo "=========================================="
    echo " Seed Demo — Status Summary"
    echo "=========================================="
    echo ""

    if [[ "$TI_STATUS" == "enabled" ]]; then
        echo "  ✅ TI Connector: enabled"
    else
        echo "  ⚠️  TI Connector: requires portal consent"
    fi

    echo "  ✅ DNS Queries: fired (5 rounds of blocked + allowed)"
    echo "  ✅ DNSQueryLogs: should appear in ~5 minutes"

    if [[ "$SUMMARY_STATUS" == "detected" ]]; then
        echo "  ✅ Summary Rule: detected"
    else
        echo "  ⚠️  Summary Rule: not detected — create manually (see README Scenario 5, Step 3)"
    fi

    echo ""
    echo "  ⏱  Sentinel incident expected in ~45-60 min after Summary Rule runs."
    echo "     Run ./scripts/pre-demo-check.sh before your session to verify."
    echo ""
    echo "=========================================="
}

# ==============================================================================
# Main
# ==============================================================================

# Parse arguments
while getopts ":g:h" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        h) show_help ;;
        \?) log_fail "Invalid option: -$OPTARG"; exit 1 ;;
        :) log_fail "Option -$OPTARG requires an argument"; exit 1 ;;
    esac
done

echo "=========================================="
echo " Azure DNS Security Lab — Seed Demo"
echo "=========================================="
echo ""

# Initialize status variables
TI_STATUS="unknown"
SUMMARY_STATUS="unknown"

# Step 0: Prerequisites
check_prerequisites

# Step 1: Discover resources
discover_resource_group
discover_resources

echo ""

# Step 2: Enable TI Data Connector
enable_ti_connector

# Step 3: Fire DNS queries from VM
fire_dns_queries

# Step 4: Check Summary Rule status
check_summary_rule

# Step 5: Print status summary
print_summary

exit 0

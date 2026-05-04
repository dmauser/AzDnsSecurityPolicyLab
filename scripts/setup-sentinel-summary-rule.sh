#!/bin/bash
#
# Script: setup-sentinel-summary-rule.sh
# Description: Automates creation of a Sentinel Summary Rule that aggregates
#              DNSQueryLogs hourly into DNSQueryLogs_sum_CL via Azure REST API.
#              Eliminates the most painful manual step in Scenario 5.
#
# Usage: ./setup-sentinel-summary-rule.sh [-g resource-group] [-w workspace-name] [-h]
#        ./setup-sentinel-summary-rule.sh
#
# Options:
#   -g resource-group   Specify the resource group name (default: auto-discover)
#   -w workspace-name   Specify the Log Analytics workspace name (default: auto-discover)
#   -h                  Display this help message and exit
#
# Requirements:
#   - az CLI (logged in with appropriate permissions)
#   - jq (for JSON parsing)
#   - Contributor or higher on the Log Analytics workspace
#
# Examples:
#   ./setup-sentinel-summary-rule.sh
#   ./setup-sentinel-summary-rule.sh -g rg-dns-security-lab -w law-dns-security-lab
#   ./setup-sentinel-summary-rule.sh -h
#
# Idempotent: Safe to run multiple times — updates existing rule if present.
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

RESOURCE_GROUP=""
WORKSPACE_NAME=""
RULE_NAME="DNSQueryLogs-hourly-summary"
DESTINATION_TABLE="DNSQueryLogs_sum_CL"
BIN_SIZE="1h"

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
}

log_fail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

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
    log_pass "Logged into Azure — subscription: $sub_name"
}

# Auto-discover resource group if not provided
discover_resource_group() {
    if [[ -n "$RESOURCE_GROUP" ]]; then
        # Validate the specified resource group exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null 2>&1; then
            log_fail "Resource group '$RESOURCE_GROUP' does not exist."
            exit 1
        fi
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

# Auto-discover workspace if not provided
discover_workspace() {
    if [[ -n "$WORKSPACE_NAME" ]]; then
        # Validate the specified workspace exists
        if ! az monitor log-analytics workspace show \
            -g "$RESOURCE_GROUP" -n "$WORKSPACE_NAME" &> /dev/null 2>&1; then
            log_fail "Workspace '$WORKSPACE_NAME' not found in resource group '$RESOURCE_GROUP'."
            exit 1
        fi
        return
    fi

    log_info "No workspace specified. Discovering from resource group..."

    WORKSPACE_NAME=$(az monitor log-analytics workspace list \
        -g "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null) || true

    if [[ -z "$WORKSPACE_NAME" || "$WORKSPACE_NAME" == "None" ]]; then
        log_fail "No Log Analytics workspace found in $RESOURCE_GROUP. Use -w to specify."
        exit 1
    fi

    log_info "Discovered workspace: $WORKSPACE_NAME"
}

# Get workspace resource ID and subscription ID
resolve_ids() {
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
    WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
        -g "$RESOURCE_GROUP" -n "$WORKSPACE_NAME" \
        --query id -o tsv 2>/dev/null)

    if [[ -z "$WORKSPACE_RESOURCE_ID" ]]; then
        log_fail "Could not resolve workspace resource ID."
        exit 1
    fi

    log_info "Subscription: $SUBSCRIPTION_ID"
    log_info "Workspace ID: $WORKSPACE_RESOURCE_ID"
}

# Check if the source table (DNSQueryLogs) exists
check_source_table() {
    log_info "Verifying DNSQueryLogs table exists in workspace..."

    local table_check
    table_check=$(az monitor log-analytics workspace table show \
        -g "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" \
        --name "DNSQueryLogs" --query "name" -o tsv 2>/dev/null) || true

    if [[ -z "$table_check" || "$table_check" == "None" ]]; then
        log_warn "DNSQueryLogs table not found. It will be created when DNS Security Policy starts logging."
        log_warn "The Summary Rule will activate once data flows into DNSQueryLogs."
    else
        log_pass "Source table DNSQueryLogs exists"
    fi
}

# Build the Summary Rule KQL query
build_kql_query() {
    # This matches the KQL in README Scenario 5, Step 3
    cat <<'EOF'
DNSQueryLogs
| extend Answer = iif(Answer == "[]", '["NXDOMAIN"]', Answer)
| extend Answer = todynamic(Answer)
| mv-expand Answer
| extend parsed = parse_json(Answer)
| extend RData = parsed.RData
| extend RType = tostring(parsed.Type)
| extend QueryName = tolower(trim_end("\\.", QueryName))
| summarize EventCount = count(), Answers = make_set(tostring(RData))
    by bin(TimeGenerated, 1h), RType, OperationName, Region, VirtualNetworkId,
       SourceIpAddress, Transport, QueryName, QueryType, ResponseCode,
       ResolutionPath, ResolverPolicyRuleAction
| extend RDataCount = array_length(Answers)
EOF
}

# Create or update the Summary Rule via REST API
create_summary_rule() {
    log_info "Creating Summary Rule '$RULE_NAME' → $DESTINATION_TABLE (bin: $BIN_SIZE)..."

    local api_version="2023-01-01-preview"
    local api_url="https://management.azure.com${WORKSPACE_RESOURCE_ID}/providers/Microsoft.OperationalInsights/summaryLogs/${RULE_NAME}?api-version=${api_version}"

    local kql_query
    kql_query=$(build_kql_query)

    # Build the request body
    local body
    body=$(jq -n \
        --arg query "$kql_query" \
        --arg dest "$DESTINATION_TABLE" \
        --arg bin "$BIN_SIZE" \
        --arg desc "Aggregates DNSQueryLogs hourly for cost-efficient Sentinel detection (Azure DNS Security Policy Lab)" \
        '{
            "properties": {
                "description": $desc,
                "query": $query,
                "binSize": $bin,
                "destinationTable": $dest,
                "isActive": true
            }
        }')

    local response
    local http_status
    set +e
    response=$(az rest \
        --method PUT \
        --url "$api_url" \
        --body "$body" \
        --headers "Content-Type=application/json" \
        2>&1)
    http_status=$?
    set -e

    if [[ $http_status -eq 0 ]]; then
        log_pass "Summary Rule created/updated successfully"
        return 0
    fi

    # Handle specific error cases
    if echo "$response" | grep -qi "AuthorizationFailed\|Forbidden\|403"; then
        log_fail "Insufficient permissions. You need Contributor or higher on the workspace."
        log_info "Required: Microsoft.OperationalInsights/workspaces/summaryLogs/write"
        exit 1
    fi

    if echo "$response" | grep -qi "ResourceNotFound\|404"; then
        log_warn "Summary Logs API may not be available in this region or API version."
        log_info "Trying alternative API endpoint..."
        create_summary_rule_alternative
        return $?
    fi

    if echo "$response" | grep -qi "already exists\|conflict\|409"; then
        log_pass "Summary Rule already exists (idempotent — no changes needed)"
        return 0
    fi

    # Unknown error — print details
    log_fail "Failed to create Summary Rule"
    log_info "Response: $response"
    log_info ""
    log_info "If this API is not yet available in your region, create the rule manually:"
    log_info "  Sentinel → Summary Rules → Create (see README Scenario 5, Step 3)"
    exit 1
}

# Alternative endpoint — uses the data collection rule approach
create_summary_rule_alternative() {
    log_info "Attempting via workspace summarize settings endpoint..."

    local api_version="2022-10-01"
    local api_url="https://management.azure.com${WORKSPACE_RESOURCE_ID}/summarizeLogs/${RULE_NAME}?api-version=${api_version}"

    local kql_query
    kql_query=$(build_kql_query)

    local body
    body=$(jq -n \
        --arg query "$kql_query" \
        --arg dest "$DESTINATION_TABLE" \
        --arg bin "$BIN_SIZE" \
        --arg desc "Aggregates DNSQueryLogs hourly for cost-efficient Sentinel detection" \
        '{
            "properties": {
                "description": $desc,
                "query": $query,
                "binSize": $bin,
                "destinationTable": $dest,
                "isActive": true
            }
        }')

    local response
    local http_status
    set +e
    response=$(az rest \
        --method PUT \
        --url "$api_url" \
        --body "$body" \
        --headers "Content-Type=application/json" \
        2>&1)
    http_status=$?
    set -e

    if [[ $http_status -eq 0 ]]; then
        log_pass "Summary Rule created/updated via alternative endpoint"
        return 0
    fi

    log_fail "Both API endpoints failed. Summary Rule must be created via portal."
    log_info "Response: $response"
    log_info ""
    log_info "Manual steps: Sentinel → Summary Rules → Create"
    log_info "  - Aggregation interval: 1 hour"
    log_info "  - Destination table: $DESTINATION_TABLE"
    log_info "  - KQL: (see README Scenario 5, Step 3)"
    exit 1
}

# Verify the rule was created
verify_rule() {
    log_info "Verifying Summary Rule status..."

    local api_version="2023-01-01-preview"
    local api_url="https://management.azure.com${WORKSPACE_RESOURCE_ID}/providers/Microsoft.OperationalInsights/summaryLogs/${RULE_NAME}?api-version=${api_version}"

    local response
    set +e
    response=$(az rest --method GET --url "$api_url" 2>&1)
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        local is_active
        is_active=$(echo "$response" | jq -r '.properties.isActive // empty' 2>/dev/null) || true
        if [[ "$is_active" == "true" ]]; then
            log_pass "Summary Rule is active and running"
        else
            log_warn "Summary Rule exists but may not be active yet"
        fi
    else
        log_info "Could not verify rule status (non-blocking — rule may still be provisioning)"
    fi
}

# Print final summary
print_summary() {
    echo ""
    echo "=========================================="
    echo " Summary Rule Setup — Complete"
    echo "=========================================="
    echo ""
    echo "  Rule Name:          $RULE_NAME"
    echo "  Source Table:        DNSQueryLogs"
    echo "  Destination Table:   $DESTINATION_TABLE"
    echo "  Aggregation:         $BIN_SIZE (hourly)"
    echo "  Workspace:           $WORKSPACE_NAME"
    echo "  Resource Group:      $RESOURCE_GROUP"
    echo ""
    echo "  ⏱  First aggregated data will appear in $DESTINATION_TABLE"
    echo "     within 1-2 hours after DNS queries flow into DNSQueryLogs."
    echo ""
    echo "  Next steps:"
    echo "    • Run ./scripts/seed-demo.sh to generate DNS query traffic"
    echo "    • Sentinel Analytics Rules will detect threats from $DESTINATION_TABLE"
    echo ""
    echo "=========================================="
}

# ==============================================================================
# Main
# ==============================================================================

# Parse arguments
while getopts ":g:w:h" opt; do
    case "$opt" in
        g) RESOURCE_GROUP="$OPTARG" ;;
        w) WORKSPACE_NAME="$OPTARG" ;;
        h) show_help ;;
        \?) log_fail "Invalid option: -$OPTARG"; exit 1 ;;
        :) log_fail "Option -$OPTARG requires an argument"; exit 1 ;;
    esac
done

echo "=========================================="
echo " Azure DNS Security Lab — Summary Rule"
echo "=========================================="
echo ""

# Step 0: Prerequisites
check_prerequisites

# Step 1: Discover/validate resources
discover_resource_group
discover_workspace
resolve_ids

echo ""

# Step 2: Check source table
check_source_table

# Step 3: Create the Summary Rule
create_summary_rule

# Step 4: Verify
verify_rule

# Step 5: Summary
print_summary

exit 0

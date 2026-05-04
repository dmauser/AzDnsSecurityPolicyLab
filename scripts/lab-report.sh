#!/bin/bash
#
# Script: lab-report.sh
# Description: Lab completion artifact script. After running all 5 lab scenarios,
#              learners can capture proof of completion. This script gathers
#              deployed resources, DNS test results, log counts, and Sentinel
#              incident status, then renders a text-art completion summary.
#
# Usage: ./lab-report.sh [-g resource-group] [-h]
#        ./lab-report.sh
#
# Options:
#   -g resource-group  Specify the resource group name (default: rg-dns-security-lab)
#   -h                 Display this help message and exit
#
# Requirements:
#   - az CLI (logged in with appropriate permissions)
#   - jq (for JSON parsing)
#
# Safety: This script is READ-ONLY — it makes no modifications.
#
# Examples:
#   ./lab-report.sh                          (use default resource group)
#   ./lab-report.sh -g my-dns-lab-rg         (specify resource group)
#   ./lab-report.sh -h                       (display help)
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

RESOURCE_GROUP="rg-dns-security-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DNS_PASS=0
DNS_FAIL=0
RESOURCE_COUNT=0
LOG_COUNT=0
SENTINEL_INCIDENTS=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test domains: domains that should be BLOCKED by DNS Security Policy
BLOCKED_DOMAINS=("malicious.contoso.com" "exploit.adatum.com" "badsite.fabrikam.com")
# Test domains: domains that should be ALLOWED
ALLOWED_DOMAINS=("www.microsoft.com" "learn.microsoft.com")

# ==============================================================================
# Functions
# ==============================================================================

show_help() {
    grep "^#" "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

print_header() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_pass() {
    echo -e "  ${GREEN}✅ $1${NC}"
}

print_fail() {
    echo -e "  ${RED}❌ $1${NC}"
}

print_info() {
    echo -e "  ${BOLD}ℹ️  $1${NC}"
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
# Prerequisites check
# ==============================================================================

check_prerequisites() {
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ az CLI not found. Install from https://aka.ms/installazurecli${NC}"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}❌ jq not found. Install with: sudo apt-get install -y jq${NC}"
        exit 1
    fi

    if ! az account show &> /dev/null 2>&1; then
        echo -e "${RED}❌ Not logged into Azure CLI. Run 'az login' first.${NC}"
        exit 1
    fi
}

# ==============================================================================
# Section 1: Subscription & Environment Info
# ==============================================================================

gather_environment() {
    print_header "ENVIRONMENT"

    local sub_name sub_id tenant_id
    sub_name=$(az account show --query name -o tsv 2>/dev/null) || sub_name="unknown"
    sub_id=$(az account show --query id -o tsv 2>/dev/null) || sub_id="unknown"
    tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null) || tenant_id="unknown"

    echo -e "  Subscription:    ${BOLD}${sub_name}${NC}"
    echo -e "  Subscription ID: ${sub_id}"
    echo -e "  Tenant ID:       ${tenant_id}"
    echo -e "  Resource Group:  ${BOLD}${RESOURCE_GROUP}${NC}"
    echo -e "  Timestamp:       $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
}

# ==============================================================================
# Section 2: Resource Summary
# ==============================================================================

gather_resources() {
    print_header "DEPLOYED RESOURCES"

    local exists
    exists=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null) || exists="false"

    if [[ "$exists" != "true" ]]; then
        print_fail "Resource group '$RESOURCE_GROUP' not found"
        return
    fi

    print_pass "Resource group exists: $RESOURCE_GROUP"

    # Key resource types to check
    local -a resource_checks=(
        "Virtual Network|Microsoft.Network/virtualNetworks"
        "DNS Resolver|Microsoft.Network/dnsResolvers"
        "DNS Security Policy|Microsoft.Network/dnsResolverPolicies"
        "Virtual Machine|Microsoft.Compute/virtualMachines"
        "Log Analytics Workspace|Microsoft.OperationalInsights/workspaces"
        "Sentinel (SecurityInsights)|Microsoft.OperationsManagement/solutions"
        "Network Security Group|Microsoft.Network/networkSecurityGroups"
    )

    for check in "${resource_checks[@]}"; do
        local display_name="${check%%|*}"
        local type_filter="${check##*|}"
        local count

        count=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length([?contains(type, '$type_filter')])" \
            -o tsv 2>/dev/null) || count="0"

        if [[ "$count" -gt 0 ]]; then
            print_pass "$display_name ($count)"
            RESOURCE_COUNT=$((RESOURCE_COUNT + count))
        else
            print_fail "$display_name — not found"
        fi
    done

    echo ""
    print_info "Total key resources: $RESOURCE_COUNT"
    echo ""
}

# ==============================================================================
# Section 3: DNS Test Results
# ==============================================================================

run_dns_tests() {
    print_header "DNS SECURITY TESTS"

    # Find the VM's private IP for DNS resolution through the resolver
    local vm_ip resolver_ip
    vm_ip=$(az vm list-ip-addresses \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].virtualMachine.network.privateIpAddresses[0]" \
        -o tsv 2>/dev/null) || vm_ip=""

    # Find the DNS resolver inbound endpoint IP
    local resolver_id
    resolver_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(type, 'Microsoft.Network/dnsResolvers')].id | [0]" \
        -o tsv 2>/dev/null) || resolver_id=""

    if [[ -n "$resolver_id" && "$resolver_id" != "None" ]]; then
        resolver_ip=$(az rest \
            --method GET \
            --url "${resolver_id}/inboundEndpoints?api-version=2022-07-01" \
            --query "value[0].properties.ipConfigurations[0].privateIpAddress" \
            -o tsv 2>/dev/null) || resolver_ip=""
    fi

    if [[ -z "$resolver_ip" || "$resolver_ip" == "None" ]]; then
        print_info "DNS Resolver inbound IP not found — running tests via VM (if available)"
        # Fall back: try to run nslookup via VM run-command
        if [[ -z "$vm_ip" || "$vm_ip" == "None" ]]; then
            print_fail "Cannot run DNS tests: no VM or resolver IP found"
            return
        fi

        local vm_name
        vm_name=$(az vm list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" \
            -o tsv 2>/dev/null) || vm_name=""

        if [[ -z "$vm_name" ]]; then
            print_fail "Cannot identify VM for DNS tests"
            return
        fi

        echo -e "  Testing blocked domains (expect NXDOMAIN/SERVFAIL)..."
        for domain in "${BLOCKED_DOMAINS[@]}"; do
            local result
            result=$(az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --command-id RunShellScript \
                --scripts "nslookup $domain 2>&1 || true" \
                --query "value[0].message" \
                -o tsv 2>/dev/null) || result=""

            if echo "$result" | grep -qiE "NXDOMAIN|SERVFAIL|server can't find|connection timed out"; then
                print_pass "BLOCKED: $domain"
                ((DNS_PASS++))
            else
                print_fail "NOT BLOCKED: $domain"
                ((DNS_FAIL++))
            fi
        done

        echo ""
        echo -e "  Testing allowed domains (expect resolution)..."
        for domain in "${ALLOWED_DOMAINS[@]}"; do
            local result
            result=$(az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --command-id RunShellScript \
                --scripts "nslookup $domain 2>&1 || true" \
                --query "value[0].message" \
                -o tsv 2>/dev/null) || result=""

            if echo "$result" | grep -qiE "Address:|address"; then
                print_pass "ALLOWED: $domain"
                ((DNS_PASS++))
            else
                print_fail "NOT RESOLVED: $domain"
                ((DNS_FAIL++))
            fi
        done
    else
        print_info "DNS Resolver IP: $resolver_ip"
        print_info "Note: Direct nslookup requires network access to the resolver."
        print_info "Falling back to VM-based tests..."

        local vm_name
        vm_name=$(az vm list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" \
            -o tsv 2>/dev/null) || vm_name=""

        if [[ -z "$vm_name" ]]; then
            print_fail "Cannot identify VM for DNS tests"
            return
        fi

        echo -e "  Testing blocked domains (expect NXDOMAIN/SERVFAIL)..."
        for domain in "${BLOCKED_DOMAINS[@]}"; do
            local result
            result=$(az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --command-id RunShellScript \
                --scripts "nslookup $domain $resolver_ip 2>&1 || true" \
                --query "value[0].message" \
                -o tsv 2>/dev/null) || result=""

            if echo "$result" | grep -qiE "NXDOMAIN|SERVFAIL|server can't find|connection timed out"; then
                print_pass "BLOCKED: $domain"
                ((DNS_PASS++))
            else
                print_fail "NOT BLOCKED: $domain"
                ((DNS_FAIL++))
            fi
        done

        echo ""
        echo -e "  Testing allowed domains (expect resolution)..."
        for domain in "${ALLOWED_DOMAINS[@]}"; do
            local result
            result=$(az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --command-id RunShellScript \
                --scripts "nslookup $domain $resolver_ip 2>&1 || true" \
                --query "value[0].message" \
                -o tsv 2>/dev/null) || result=""

            if echo "$result" | grep -qiE "Address:|address"; then
                print_pass "ALLOWED: $domain"
                ((DNS_PASS++))
            else
                print_fail "NOT RESOLVED: $domain"
                ((DNS_FAIL++))
            fi
        done
    fi

    echo ""
    print_info "DNS Tests: ${DNS_PASS} passed, ${DNS_FAIL} failed (out of $((DNS_PASS + DNS_FAIL)))"
    echo ""
}

# ==============================================================================
# Section 4: Log Analytics Query Count
# ==============================================================================

check_log_analytics() {
    print_header "LOG ANALYTICS — DNS QUERY LOGS (LAST HOUR)"

    local workspace_id
    workspace_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].name | [0]" \
        -o tsv 2>/dev/null) || workspace_id=""

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        print_fail "Log Analytics workspace not found"
        return
    fi

    # Query DNSQueryLogs for row count in last hour
    local query='DNSQueryLogs | where TimeGenerated > ago(1h) | count'
    local result
    result=$(az monitor log-analytics query \
        --workspace "$workspace_id" \
        --analytics-query "$query" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].Count" \
        -o tsv 2>/dev/null) || result=""

    if [[ -z "$result" || "$result" == "None" ]]; then
        # Try alternative: workspace might need full resource ID
        local workspace_resource_id
        workspace_resource_id=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?type=='Microsoft.OperationalInsights/workspaces'].id | [0]" \
            -o tsv 2>/dev/null) || workspace_resource_id=""

        if [[ -n "$workspace_resource_id" ]]; then
            result=$(az monitor log-analytics query \
                --workspace "$workspace_resource_id" \
                --analytics-query "$query" \
                --query "[0].Count" \
                -o tsv 2>/dev/null) || result="0"
        else
            result="0"
        fi
    fi

    LOG_COUNT="${result:-0}"

    if [[ "$LOG_COUNT" -gt 0 ]]; then
        print_pass "DNSQueryLogs rows in last hour: $LOG_COUNT"
    else
        print_fail "No DNSQueryLogs rows found in the last hour"
        print_info "Tip: Run DNS queries from the VM to generate log data"
    fi
    echo ""
}

# ==============================================================================
# Section 5: Sentinel Incidents
# ==============================================================================

check_sentinel_incidents() {
    print_header "SENTINEL INCIDENTS"

    local workspace_id
    workspace_id=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?type=='Microsoft.OperationalInsights/workspaces'].id | [0]" \
        -o tsv 2>/dev/null) || workspace_id=""

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        print_fail "Workspace not found — cannot check Sentinel incidents"
        return
    fi

    # Query Sentinel incidents via REST API
    local incidents_url="${workspace_id}/providers/Microsoft.SecurityInsights/incidents?api-version=2024-09-01&\$top=10"
    local incident_count
    incident_count=$(az rest \
        --method GET \
        --url "$incidents_url" \
        --query "value | length(@)" \
        -o tsv 2>/dev/null) || incident_count="0"

    SENTINEL_INCIDENTS="${incident_count:-0}"

    if [[ "$SENTINEL_INCIDENTS" -gt 0 ]]; then
        print_pass "Sentinel incidents found: $SENTINEL_INCIDENTS"

        # Show recent incident titles
        local titles
        titles=$(az rest \
            --method GET \
            --url "$incidents_url" \
            --query "value[].{title: properties.title, severity: properties.severity}" \
            -o json 2>/dev/null) || titles="[]"

        if [[ "$titles" != "[]" ]]; then
            echo ""
            echo -e "  ${BOLD}Recent Incidents:${NC}"
            echo "$titles" | jq -r '.[] | "    • [\(.severity)] \(.title)"' 2>/dev/null || true
        fi
    else
        print_fail "No Sentinel incidents found"
        print_info "Tip: Run Scenario 5 (seed-demo.sh) and wait for analytics rules to fire"
    fi
    echo ""
}

# ==============================================================================
# Section 6: Completion Certificate
# ==============================================================================

render_certificate() {
    local total_tests=$((DNS_PASS + DNS_FAIL))
    local dns_score="$DNS_PASS/$total_tests"

    # Determine overall status
    local status_color status_text
    if [[ "$DNS_PASS" -ge 4 && "$LOG_COUNT" -gt 0 && "$SENTINEL_INCIDENTS" -gt 0 && "$RESOURCE_COUNT" -ge 5 ]]; then
        status_color="$GREEN"
        status_text="ALL SCENARIOS COMPLETE"
    elif [[ "$DNS_PASS" -ge 3 && "$RESOURCE_COUNT" -ge 5 ]]; then
        status_color="$YELLOW"
        status_text="MOSTLY COMPLETE — Review items above"
    else
        status_color="$RED"
        status_text="INCOMPLETE — Continue lab exercises"
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}╔═╗╔═══╗╔═══╗╔═══╗╔═══╗   ╔═══╗╔═══╗╔═╗╔═╗╔═══╗${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}║ ║║   ║║   ║║   ║║       ║   ║║   ║║ ╚╝ ║║    ${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}╠═╣╠══╦╝║   ║╠═══╣╠═══╗   ║   ║║   ║║     ║╠═══╗${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}║ ║║  ╚╗║   ║║   ║    ║   ║   ║║   ║║ ╔╗ ║║    ${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}╚═╝╚═══╝╚═══╝╚═══╝╚═══╝   ╚═══╝╚═══╝╚═╝╚═╝╚═══╝${NC}            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}        ${BOLD}DNS SECURITY POLICY LAB — COMPLETION REPORT${NC}               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Resources Deployed:    ${BOLD}${RESOURCE_COUNT}${NC} key resources                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   DNS Tests Passed:      ${BOLD}${dns_score}${NC}                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   DNS Logs (last hour):  ${BOLD}${LOG_COUNT}${NC} rows                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Sentinel Incidents:    ${BOLD}${SENTINEL_INCIDENTS}${NC}                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Status: ${status_color}${status_text}${NC}                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    echo ""
    echo -e "${BOLD}Azure DNS Security Policy Lab — Completion Report${NC}"
    echo -e "═══════════════════════════════════════════════════"
    echo ""

    check_prerequisites
    gather_environment
    gather_resources
    run_dns_tests
    check_log_analytics
    check_sentinel_incidents
    render_certificate
}

main "$@"

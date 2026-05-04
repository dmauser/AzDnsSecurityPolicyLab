#!/bin/bash
#
# Script: e2e-test.sh
# Description: End-to-end DNS security pipeline validation script.
#              Runs ON THE VM (inside the VNet) to verify that Azure DNS Security
#              Policies are correctly blocking malicious domains and allowing
#              legitimate ones. Optionally checks Log Analytics for query log ingestion.
#
# Usage: ./e2e-test.sh [-w] [-t seconds] [-h]
#        ./e2e-test.sh
#
# Options:
#   -w          Wait mode — after DNS tests, poll Log Analytics for DNS query logs
#               to confirm end-to-end pipeline (DNS query → block → log ingestion)
#   -t seconds  Timeout for Log Analytics polling in seconds (default: 300)
#   -h          Display this help message and exit
#
# Requirements:
#   - dig (DNS lookup utility) - automatically installed if missing
#   - az CLI (only required for -w mode)
#   - Must be run from inside the VNet (VM connected via Bastion/SSH)
#
# Examples:
#   ./e2e-test.sh                  (run DNS validation tests only)
#   ./e2e-test.sh -w               (DNS tests + Log Analytics verification, 5min timeout)
#   ./e2e-test.sh -w -t 600        (DNS tests + Log Analytics, 10min timeout)
#   ./e2e-test.sh -h               (display help)
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

WAIT_MODE=false
TIMEOUT=300
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

BLOCKED_DOMAINS=("malicious.contoso.com" "exploit.adatum.com")
ALLOWED_DOMAINS=("google.com" "microsoft.com")

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

log_fail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1"
}

install_dig() {
    if ! command -v dig &> /dev/null; then
        log_info "dig not found. Installing dnsutils..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq dnsutils
        if ! command -v dig &> /dev/null; then
            log_fail "Failed to install dig. Cannot continue."
            exit 1
        fi
        log_pass "dig installed successfully"
    fi
}

# Run a single test case and record pass/fail
# Arguments: $1=test_name $2=expected_outcome $3=actual_result $4=pass_condition (0=pass,1=fail)
record_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local passed="$4"

    ((TESTS_TOTAL++))

    echo ""
    echo "  Test:     $test_name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"

    if [[ "$passed" -eq 0 ]]; then
        log_pass "PASS — $test_name"
        ((TESTS_PASSED++))
    else
        log_fail "FAIL — $test_name"
        ((TESTS_FAILED++))
    fi
}

# Test that a blocked domain returns NXDOMAIN or blockpolicy.azuredns.invalid
test_blocked_domain() {
    local domain="$1"
    local result
    local status

    result=$(dig "$domain" +time=5 +tries=2 2>&1) || true
    status=$(echo "$result" | grep -oP 'status: \K[A-Z]+' || echo "TIMEOUT")

    if echo "$result" | grep -qi "blockpolicy.azuredns.invalid" || [[ "$status" == "NXDOMAIN" ]]; then
        record_test "Blocked domain: $domain" \
            "NXDOMAIN or blockpolicy.azuredns.invalid" \
            "status=$status (blockpolicy detected)" \
            0
    else
        record_test "Blocked domain: $domain" \
            "NXDOMAIN or blockpolicy.azuredns.invalid" \
            "status=$status" \
            1
    fi
}

# Test that a blocked domain returns empty or blockpolicy with +short
test_blocked_domain_short() {
    local domain="$1"
    local result

    result=$(dig "$domain" +short +time=5 +tries=2 2>&1) || true

    if [[ -z "$result" ]] || echo "$result" | grep -qi "blockpolicy.azuredns.invalid"; then
        record_test "Blocked domain (+short): $domain" \
            "Empty or blockpolicy.azuredns.invalid" \
            "${result:-<empty>}" \
            0
    else
        record_test "Blocked domain (+short): $domain" \
            "Empty or blockpolicy.azuredns.invalid" \
            "$result" \
            1
    fi
}

# Test that an allowed domain returns a valid IP (NOERROR)
test_allowed_domain() {
    local domain="$1"
    local result
    local status

    result=$(dig "$domain" +time=5 +tries=2 2>&1) || true
    status=$(echo "$result" | grep -oP 'status: \K[A-Z]+' || echo "TIMEOUT")

    if [[ "$status" == "NOERROR" ]]; then
        record_test "Allowed domain: $domain" \
            "NOERROR with valid response" \
            "status=$status" \
            0
    else
        record_test "Allowed domain: $domain" \
            "NOERROR with valid response" \
            "status=$status" \
            1
    fi
}

# Test that an allowed domain returns an IP with +short
test_allowed_domain_short() {
    local domain="$1"
    local result

    result=$(dig "$domain" +short +time=5 +tries=2 2>&1) || true

    # Check if result contains at least one IP address (v4 or v6)
    if echo "$result" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|^[0-9a-fA-F:]+$'; then
        record_test "Allowed domain (+short): $domain" \
            "Valid IP address" \
            "$result" \
            0
    else
        record_test "Allowed domain (+short): $domain" \
            "Valid IP address" \
            "${result:-<empty>}" \
            1
    fi
}

# Poll Log Analytics for DNS query logs
check_log_analytics() {
    log_info "Starting Log Analytics verification (timeout: ${TIMEOUT}s)..."

    # Check az CLI availability
    if ! command -v az &> /dev/null; then
        log_warn "az CLI not found. Skipping Log Analytics check."
        return 0
    fi

    # Check az CLI login
    if ! az account show &> /dev/null 2>&1; then
        log_warn "Not logged into Azure CLI. Skipping Log Analytics check."
        log_info "Run 'az login' to enable Log Analytics verification."
        return 0
    fi

    # Find Log Analytics workspace
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace list \
        --query "[?contains(name, 'dns') || contains(name, 'law')].customerId | [0]" \
        -o tsv 2>/dev/null) || true

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        # Try to find any workspace in the resource group
        workspace_id=$(az monitor log-analytics workspace list \
            --query "[0].customerId" \
            -o tsv 2>/dev/null) || true
    fi

    if [[ -z "$workspace_id" || "$workspace_id" == "None" ]]; then
        log_warn "No Log Analytics workspace found. Skipping log verification."
        return 0
    fi

    log_info "Found workspace: $workspace_id"
    log_info "Polling for DNS query logs (malicious.contoso.com)..."

    local query='DNSQueryLogs | where QueryName contains "malicious.contoso.com" | where TimeGenerated > ago(10m) | count'
    local elapsed=0
    local poll_interval=30

    while [[ $elapsed -lt $TIMEOUT ]]; do
        local count
        count=$(az monitor log-analytics query \
            --workspace "$workspace_id" \
            --analytics-query "$query" \
            --query "[0].Count" \
            -o tsv 2>/dev/null) || true

        if [[ -n "$count" && "$count" != "0" && "$count" != "None" ]]; then
            echo ""
            log_pass "End-to-end pipeline confirmed: DNS query → block → log ingestion ✅"
            log_info "Found $count DNS query log entries for malicious.contoso.com"
            return 0
        fi

        elapsed=$((elapsed + poll_interval))
        if [[ $elapsed -lt $TIMEOUT ]]; then
            log_info "No logs yet... retrying in ${poll_interval}s (${elapsed}s/${TIMEOUT}s elapsed)"
            sleep "$poll_interval"
        fi
    done

    log_warn "Log Analytics check timed out after ${TIMEOUT}s."
    log_info "Logs may take several minutes to appear. Try again later or increase timeout with -t."
    return 1
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  E2E DNS Security Test Summary"
    echo "=========================================="
    echo ""
    echo "  Total:  $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED ✅"
    echo "  Failed: $TESTS_FAILED ❌"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "  Result: ALL TESTS PASSED ✅"
    else
        echo "  Result: SOME TESTS FAILED ❌"
    fi
    echo ""
    echo "=========================================="
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -w)
            WAIT_MODE=true
            shift
            ;;
        -t)
            TIMEOUT="$2"
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
echo "  Azure DNS Security Policy — E2E Test"
echo "=========================================="
echo ""
log_info "Starting end-to-end DNS security validation..."
echo ""

# Prerequisites
install_dig

# --- Blocked Domain Tests ---
echo ""
echo "------------------------------------------"
echo "  Blocked Domain Tests"
echo "------------------------------------------"

for domain in "${BLOCKED_DOMAINS[@]}"; do
    test_blocked_domain "$domain"
done

# --- Allowed Domain Tests ---
echo ""
echo "------------------------------------------"
echo "  Allowed Domain Tests"
echo "------------------------------------------"

for domain in "${ALLOWED_DOMAINS[@]}"; do
    test_allowed_domain "$domain"
done

# --- Detailed Blocked Tests (+short) ---
echo ""
echo "------------------------------------------"
echo "  Detailed Blocked Tests (+short)"
echo "------------------------------------------"

for domain in "${BLOCKED_DOMAINS[@]}"; do
    test_blocked_domain_short "$domain"
done

# --- Detailed Allowed Tests (+short) ---
echo ""
echo "------------------------------------------"
echo "  Detailed Allowed Tests (+short)"
echo "------------------------------------------"

for domain in "${ALLOWED_DOMAINS[@]}"; do
    test_allowed_domain_short "$domain"
done

# --- Summary ---
print_summary

# --- Optional: Log Analytics Check ---
if [[ "$WAIT_MODE" == true ]]; then
    echo ""
    echo "------------------------------------------"
    echo "  Log Analytics Pipeline Verification"
    echo "------------------------------------------"
    echo ""
    check_log_analytics
fi

# Exit with appropriate code
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0

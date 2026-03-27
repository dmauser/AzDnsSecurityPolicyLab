#!/bin/bash
#
# Script: dnstest.sh
# Description: DNS security testing utility that queries domains against a blacklist.
#              Downloads a blacklist of known malicious/suspicious domains and performs
#              DNS lookups (dig queries) on each domain to verify their resolution status.
#
# Usage: ./dnstest.sh [-q keyword] [-h]
#        ./dnstest.sh
#
# Options:
#   -q keyword  Search keyword to filter blacklist domains (optional)
#               Example: ./dnstest.sh -q blob.core.windows.net
#   -h          Display this help message and exit
#
# Output:
#   - Console output with timestamped log messages
#   - dnstest_<timestamp>[_keyword].log file containing query results and status
#
# Requirements:
#   - dig (DNS lookup utility) - automatically installed if missing
#   - curl (for downloading blacklist)
#   - sudo privileges (for package installation if needed)
#
# Blacklist Source:
#   https://github.com/fabriziosalmi/blacklists/releases/download/latest/blacklist.txt
#
# Examples:
#   ./dnstest.sh                           (queries all domains)
#   ./dnstest.sh -q blob.core.windows.net  (queries only matching domains)
#   ./dnstest.sh -h                        (display help)
#

# Parse arguments first to determine log file name
SEARCH_KEYWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -q)
            SEARCH_KEYWORD="$2"
            shift 2
            ;;
        -h)
            grep "^#" "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Set log file with timestamp and optional keyword
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
if [[ -n "$SEARCH_KEYWORD" ]]; then
    LOG_FILE="dnstest_${TIMESTAMP}_${SEARCH_KEYWORD}.log"
else
    LOG_FILE="dnstest_${TIMESTAMP}.log"
fi

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if dig is installed, install if not
if ! command -v dig &> /dev/null; then
    log_message "dig not found. Installing dnsutils..."
    sudo apt-get update
    sudo apt-get install -y dnsutils
fi

# Download the blacklist
log_message "Downloading blacklist..."
curl -L https://github.com/fabriziosalmi/blacklists/releases/download/latest/blacklist.txt -o blacklist.txt

# Run dig against each domain in the blacklist
log_message "Running dig queries..."
if [[ -n "$SEARCH_KEYWORD" ]]; then
    log_message "Filtering by keyword: $SEARCH_KEYWORD"
fi
log_message "=================================================="

count=0
while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]] && continue
    
    # Filter by keyword if provided
    if [[ -n "$SEARCH_KEYWORD" && ! "$domain" =~ $SEARCH_KEYWORD ]]; then
        continue
    fi
    
    ((count++))
    echo ""
    log_message "[$count] Querying: $domain"
    dig "$domain" +short | tee -a "$LOG_FILE"
done < blacklist.txt

log_message "=================================================="
log_message "Done! Processed $count domains."
log_message "Results saved to: $LOG_FILE"
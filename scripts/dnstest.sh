#!/bin/bash
#
# Script: dnstest.sh
# Description: DNS security testing utility that queries domains against a blacklist.
#              Downloads a blacklist of known malicious/suspicious domains and performs
#              DNS lookups (dig queries) on each domain to verify their resolution status.
#
# Usage: ./dnstest.sh [keyword]
#        ./dnstest.sh -h
#
# Options:
#   keyword     Search keyword to filter blacklist domains (optional)
#               Example: ./dnstest.sh malware
#   -h          Display this help message and exit
#
# Output:
#   - Console output with timestamped log messages
#   - dnstest.log file containing query results and status
#
# Requirements:
#   - dig (DNS lookup utility) - automatically installed if missing
#   - curl (for downloading blacklist)
#   - sudo privileges (for package installation if needed)
#
# Blacklist Source:
#   https://github.com/fabriziosalmi/blacklists/releases/download/latest/blacklist.txt
#
# Example:
#   ./dnstest.sh malware
#   ./dnstest.sh -h
#

# Set log file
LOG_FILE="dnstest.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log messages
SEARCH_KEYWORD="${1:-}"

if [[ -z "$SEARCH_KEYWORD" ]]; then
    log_message "Usage: $0 [keyword]"
    log_message "Example: $0 malware"
    exit 1
fi
log_message() {
    echo "[${TIMESTAMP}] $1" | tee -a "$LOG_FILE"
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
log_message "=================================================="

count=0
while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]] && continue
    ((count++))
    echo ""
    log_message "[$count] Querying: $domain"
    dig "$domain" +short | tee -a "$LOG_FILE"
done < blacklist.txt

log_message "=================================================="
log_message "Done! Processed $count domains."
log_message "Results saved to: $LOG_FILE"
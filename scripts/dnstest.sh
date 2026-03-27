#!/bin/bash

# Set log file
LOG_FILE="dnstest.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log messages
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
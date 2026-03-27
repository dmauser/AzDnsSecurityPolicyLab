#!/bin/bash

# Check if dig is installed, install if not
if ! command -v dig &> /dev/null; then
    echo "dig not found. Installing dnsutils..."
    sudo apt-get update
    sudo apt-get install -y dnsutils
fi

# Download the blacklist
echo "Downloading blacklist..."
curl -L https://github.com/fabriziosalmi/blacklists/releases/download/latest/blacklist.txt -o blacklist.txt

# Run dig against each domain in the blacklist
echo "Running dig queries..."
while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" =~ ^[[:space:]]*# ]] && continue
    echo "=== Querying $domain ==="
    dig "$domain" +short
done < blacklist.txt

echo "Done!"
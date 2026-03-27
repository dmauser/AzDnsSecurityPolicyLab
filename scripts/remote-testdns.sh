#!/bin/bash

# Run nslookup commands against the Ubuntu VM
az vm run-command invoke `
    --resource-group "rg-dns-security-lab" `
    --name "vm-ubuntu-lab" `
    --command-id RunShellScript `
    --scripts "nslookup malicious.contoso.com" "nslookup exploit.adatum.com"
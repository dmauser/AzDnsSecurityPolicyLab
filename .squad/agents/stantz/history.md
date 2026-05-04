# Project Context

- **Owner:** Daniel
- **Project:** Azure DNS Security Policy Lab — Bicep IaC for DNS security policies, Sentinel, Codespaces
- **Stack:** Bicep, ARM, PowerShell, Bash, Azure CLI, Azure DNS, Sentinel, Log Analytics
- **Created:** 2026-05-04

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-05-04**: Created `scripts/e2e-test.sh` — end-to-end DNS security validation script.
  - Blocked domains: `malicious.contoso.com`, `exploit.adatum.com` (from `infra/main.bicep` domainList)
  - Expected block response: NXDOMAIN status or `blockpolicy.azuredns.invalid` in answer
  - Allowed domains: `google.com`, `microsoft.com` — must return NOERROR with valid IPs
  - Script runs ON the VM inside the VNet (Bastion/SSH access)
  - Optional `-w` flag polls Log Analytics for `DNSQueryLogs` to confirm full pipeline
  - Style follows `validate-environment.sh` (emoji pass/fail, functions, EXIT_CODE pattern)
  - `dnstest.sh` auto-installs dig via `sudo apt-get install -y dnsutils` — same pattern reused
  - Log Analytics query: `DNSQueryLogs | where QueryName contains "malicious.contoso.com" | where TimeGenerated > ago(10m) | count`

- **2026-05-04**: Created `scripts/verify-lab.sh` — post-deploy verification (runs from deployer's machine).
  - Checks: RG, VM, VNet, Bastion, Log Analytics, DNS Security Policy, DNS Resolver, Key Vault
  - Verifies DNS policy is linked to VNet via `virtualNetworkLinks` REST endpoint
  - Verifies domain list contains trailing-dot domains (`malicious.contoso.com.`, `exploit.adatum.com.`)
  - Verifies diagnostic settings on dnsResolverPolicies resource
  - Verifies Sentinel solution + analytics rules (expects ≥2 TI rules)
  - Auto-discovers RG by matching name containing 'dns', or accepts `-g` flag
  - API versions: `2023-06-01` for DNS resolver resources, `2024-09-01` for Sentinel alertRules
  - Two-script validation strategy: `verify-lab.sh` (from outside) + `e2e-test.sh` (from inside VM)

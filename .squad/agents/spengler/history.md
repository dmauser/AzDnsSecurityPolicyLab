# Project Context

- **Owner:** Daniel
- **Project:** Azure DNS Security Policy Lab — Bicep IaC for DNS security policies, Sentinel, Codespaces
- **Stack:** Bicep, ARM, PowerShell, Bash, Azure CLI, Azure DNS, Sentinel, Log Analytics
- **Created:** 2026-05-04

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-04 — Sentinel Analytics Rules added to infra/main.bicep
- Sentinel alert rules use `Microsoft.SecurityInsights/alertRules@2024-09-01` with `scope: logAnalyticsWorkspace`.
- The `name` field uses `guid(workspace.id, 'rule-slug')` for deterministic resource naming.
- KQL queries sourced from README Scenario 5 (based on @pisinger's blog).
- TI data connector and Summary Rules are portal-only — cannot be automated via Bicep/ARM.
- Bicep triple-quote (`'''`) syntax works well for multi-line KQL without escaping issues.
- Key file: `infra/main.bicep` lines ~354–490 (after `sentinel` solution resource).

### 2026-05-04 — Sentinel Demo Script (scripts/seed-demo.sh) Added
- Created `scripts/seed-demo.sh` as "warm-the-lab" script for Sentinel demo prep
- Populates sample DNS query logs into Log Analytics prior to live demo execution
- Enables Sentinel TI rules to fire predictably during demo walk-through
- Status: Implemented and ready for demo workflow integration

### 2026-05-04 — Custom Script Extension for DNS Testing Tools
- Added `Microsoft.Compute/virtualMachines/extensions@2024-03-01` (CustomScript) to Linux VM.
- Extension installs `dnsutils`, `curl`, `jq` and creates `/home/azureuser/dns-quick-test.sh`.
- Gated behind `installDnsTools` bool parameter (default: true).
- Cloud-init also expanded to install `curl` and `jq` alongside `dnsutils` for belt-and-suspenders reliability.
- Using `parent: vm` syntax eliminates need for explicit `dependsOn`.
- Only pre-existing warning: Key Vault `utcNow` nondeterministic name (acceptable).

### 2026-05-04 — Log Analytics Workbook added to infra/main.bicep
- Resource type: `Microsoft.Insights/workbooks@2022-04-01`, gated by `deployWorkbook` bool param (default true).
- `serializedData` uses Bicep `string()` wrapping a native object literal — cleaner than inline JSON strings.
- Workbook name uses `guid(workspace.id, 'dns-security-workbook')` for deterministic naming (same pattern as Sentinel rules).
- Four panels: Blocked vs Allowed pie chart, Top 10 Blocked Domains bar chart, DNS Query Timeline timechart, Source IP Analysis table.
- KQL targets `DNSQueryLogs` native table (not the summary custom table).
- Validated with `az bicep build` — no new warnings beyond pre-existing Key Vault utcNow.

### 2026-05-04 — VM Pre-Configuration via Custom Script Extension + Cloud-Init (P1 Wave)
- Dual approach: Cloud-init installs `dnsutils`, `curl`, `jq` during first boot; Custom Script Extension post-provisioning backup.
- Extension creates `/home/azureuser/dns-quick-test.sh` helper script for ad-hoc DNS testing.
- Gated by `installDnsTools` param (default true) — no breaking changes.
- Adds ~15s to VM provisioning time for extension completion.
- Belt-and-suspenders strategy ensures tools availability regardless of cloud-init timing/races.

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

### 2026-05-04 — Sentinel Summary Rule Automation Script (P2-2)
- Created `scripts/setup-sentinel-summary-rule.sh` to automate the most painful manual step in Scenario 5.
- Uses `az rest --method PUT` against `Microsoft.OperationalInsights/summaryLogs/{ruleName}` endpoint (API version 2023-01-01-preview).
- Includes fallback to alternative endpoint path if primary returns 404 (API availability varies by region).
- KQL query matches README Scenario 5, Step 3 exactly — aggregates DNSQueryLogs hourly into DNSQueryLogs_sum_CL.
- Script is idempotent: PUT is naturally create-or-update; explicit 409/conflict handling as well.
- Follows same style conventions as seed-demo.sh (log_info/pass/warn/fail, getopts, auto-discovery pattern).
- Summary Logs REST API is preview — may change. Script provides clear manual fallback instructions if API fails.

### 2026-05-04 — Lab Completion Report Script (scripts/lab-report.sh)
- Created `scripts/lab-report.sh` as a read-only completion artifact (P2-3 task).
- Gathers: resource inventory, DNS block/allow tests via VM run-command, Log Analytics DNSQueryLogs count, Sentinel incidents via REST API.
- Renders a colorized text-art "Lab Completion Certificate" banner suitable for screenshots.
- Follows project conventions: `set -euo pipefail`, getopts `-g`/`-h`, color helpers, same resource discovery patterns.
- DNS tests use `az vm run-command invoke` + nslookup (same approach as verify-lab.sh) targeting 5 domains (3 blocked, 2 allowed).
- Sentinel incidents queried via `Microsoft.SecurityInsights/incidents` REST endpoint (api-version 2024-09-01).
- Default resource group: `rg-dns-security-lab` (matching lab README convention).

### 2026-05-04 — Key Vault Soft-Delete Idempotency Handler (P2-6)
- Added `VaultAlreadyExists` / soft-delete error handler to `scripts/deploy-lab.sh`.
- Matches existing error-handling pattern (SKU, Bastion) — new `elif` branch with grep -qi.
- Recovery guidance: `az keyvault purge` or wait ≥1 minute for new utcNow()-based name.
- Added explanatory comment above deployment command documenting WHY utcNow() is used.
- The grep pattern covers: VaultAlreadyExists, soft.delete, SoftDeletedVault, "already exists in a deleted state".

### 2026-05-04 — Decision: Summary Rule Automation (Recorded in decisions.md)
- Spengler's Summary Rule automation proposal documented and merged into canonical decisions.md.
- Rationale: Eliminates manual portal step, uses preview API defensively, idempotent safety.

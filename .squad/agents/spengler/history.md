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

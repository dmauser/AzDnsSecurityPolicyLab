# Decisions Log

## 2026-05-04: Sentinel Analytics Rules in Bicep
**Author:** Spengler | **Status:** Implemented

The lab provisions automated Sentinel analytics rules (Scheduled kind, API v2024-09-01) that detect DNS queries matching Threat Intelligence indicators. Two rule types: domain-based and IP-based detection. Both are scoped to Log Analytics workspace, depend on Sentinel solution, use deterministic naming (guid-based), run hourly with 14-day TI lookback, and create incidents with entity grouping. TI data connector and Summary Rule require manual portal enablement.

---

## 2026-05-04: E2E Test Script Structure
**Author:** Stantz | **Status:** Implemented

`scripts/e2e-test.sh` serves as canonical end-to-end validation running ON the VM inside VNet. Key decisions: (1) Block detection accepts both NXDOMAIN and `blockpolicy.azuredns.invalid`; (2) Log Analytics polling optional via `-w` flag, graceful skip on missing CLI/auth; (3) 5-min default timeout for polling, configurable via `-t`; (4) Exit 0 only if ALL DNS tests pass—LA timeout is warning not failure.

---

## 2026-05-04: Post-Deploy Verification Script
**Author:** Stantz | **Status:** Implemented

`scripts/verify-lab.sh` complements `e2e-test.sh` with deployer-side validation. Key decisions: (1) Auto-discovers resource group by 'dns' name match, fallback `-g` flag; (2) Uses REST API (`az rest`, v2023-06-01) for DNS policy checks since `az dns-resolver` extension may be unavailable; (3) Expects ≥2 Sentinel analytics rules (TI rules), warns if 1, fails if 0; (4) Validates diagnostic settings existence only; (5) Checks for trailing-dot domain format (`malicious.contoso.com.`) per Azure DNS requirements.

---

## 2026-05-04: Log Analytics Workbook for DNS Security Dashboard
**Author:** Spengler | **Status:** Implemented

Added `Microsoft.Insights/workbooks@2022-04-01` to `infra/main.bicep` with four panels: (1) Blocked vs Allowed Queries — Pie chart by `ResolverPolicyRuleAction`; (2) Top 10 Blocked Domains — Bar chart of most-blocked `QueryName` values; (3) DNS Query Timeline — Timechart (5-min bins) split by action type; (4) Source IP Analysis — Table of IPs generating blocked queries. Gated by `deployWorkbook` param (default true). Workbook deploys in single `az deployment group create`; uses `string()` on Bicep object for clean ARM compilation; leverages `DNSQueryLogs` native table for real-time accuracy.

---

## 2026-05-04: VM Pre-Configuration via Custom Script Extension + Cloud-Init
**Author:** Spengler | **Status:** Implemented

Dual approach for VM bootstrapping: (1) Cloud-init (already in place) installs `dnsutils`, `curl`, `jq` during first boot; (2) Custom Script Extension runs post-provisioning to ensure packages are installed and creates `/home/azureuser/dns-quick-test.sh` helper script. Extension gated behind `installDnsTools` param (default true). Belt-and-suspenders strategy: cloud-init covers first-boot, CSE covers cases where cloud-init races or is skipped. Inline `commandToExecute` keeps template self-contained. No breaking changes; adds ~15s to VM provisioning time.

---

## 2026-05-04: Educational Callouts for Scenario Learning
**Author:** Zeddemore | **Status:** Implemented

Added educational callouts (> 💡 **What Just Happened?**) after each of the five lab scenarios in README.md, plus screenshot placeholders for Sentinel output in Scenario 5. Each callout explains the security mechanism, real-world relevance, and SOC workflow mapping. Callout scope: (1) DNS Security Policy blocks at resolver level; (2) Real-time policy updates without restart; (3) DNS as universal telemetry source; (4) Layered threat intelligence; (5) Correlation engine (DNS + TI + rules). Added "Expected Sentinel Output" section describing incident format, timing (~1 hour), and user actions. Uses existing markdown blockquote syntax with emoji (💡, 📸) for visual scannability; language targets first-time lab users without DNS/Sentinel expertise.

---

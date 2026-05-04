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

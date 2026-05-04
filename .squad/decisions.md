# Squad Decisions

## Active Decisions

### Decision: Summary Rule Automation via Preview REST API

**Author:** Spengler
**Date:** 2026-05-04
**Status:** Proposed

#### Context

The README documents Summary Rule creation as portal-only (Scenario 5, Step 3). The REST API for Summary Logs (`Microsoft.OperationalInsights/summaryLogs`) is callable via `az rest` but uses a **preview** API version (`2023-01-01-preview`).

#### Decision

Created `scripts/setup-sentinel-summary-rule.sh` that automates Summary Rule creation via the preview REST API, with graceful fallback to manual instructions if the API is unavailable in a given region.

#### Rationale

- Eliminates the most painful manual step in the lab setup
- Preview APIs are acceptable for lab/demo tooling (not production)
- Script is defensive: validates workspace, checks permissions, provides clear manual steps if API fails
- Idempotent via PUT semantics — safe to run repeatedly

#### Trade-offs

- Preview API may break or change without notice
- If API is deprecated, script will still fail gracefully with manual instructions
- Not using Bicep because Summary Rules are not exposed as ARM resource types (yet)

#### Impact

- `scripts/setup-sentinel-summary-rule.sh` — new file
- `seed-demo.sh` can reference this script for full automation workflow

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

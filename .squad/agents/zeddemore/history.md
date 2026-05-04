# Project Context

- **Owner:** Daniel
- **Project:** Azure DNS Security Policy Lab — Bicep IaC for DNS security policies, Sentinel, Codespaces
- **Stack:** Bicep, ARM, PowerShell, Bash, Azure CLI, Azure DNS, Sentinel, Log Analytics
- **Created:** 2026-05-04

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-04 — Scenario-Specific Learning Resources Table (P2-5)
- Replaced generic "Learning Resources" section (4 outdated docs.microsoft.com links) with scenario-mapped table in README.md
- Table includes General row + 5 lab scenarios, each linked to specific Microsoft Learn documentation
- Verified all 6 links are current: dns-security-policy, dns-private-resolver-overview, sentinel/summary-rules, sentinel/detect-threats-custom
- Table structure: Scenario | Topic | Microsoft Learn (with short link text for scannability)
- Scenario 5 (Sentinel Integration) includes dual links (Summary Rules + Analytics Rules) to cover both rule types
- Improves discoverability: users now see why each scenario matters and where to learn deeper concepts
- Aligns with user-first documentation approach: link text describes what user will learn, not just doc title

### 2026-05-04 — DNS Block → Sentinel Flow Sequence Diagram
- Added Mermaid `sequenceDiagram` to README.md in new "How It Works" section BEFORE Scenarios
- Visualizes all 9 steps: DNS query → policy block → LAW logging → Summary Rule aggregation → Sentinel Analytics → TI lookup → Incident
- Complements static architecture diagram with dynamic data flow narrative
- Includes reference table mapping steps to components for quick understanding
- Helps first-time users grasp how DNS blocking integrates with threat detection

### 2026-05-04 — Educational Callouts + Sentinel Screenshots
- Added "What Just Happened?" callouts to all five scenarios explaining security mechanisms in user-friendly terms
- Each callout bridges from lab exercise to real-world threat scenarios (C2 callbacks, incident response, data exfiltration, threat intel, SOC automation)
- Added screenshot placeholder section in Scenario 5 (Sentinel) with guidance on expected incident output and timing
- Improves onboarding for users new to DNS security and threat detection workflows

### 2026-05-04 — Educational Callouts in P1 Wave (Consolidated)
- Final callout scope: Scenarios 1–5 each have blockquote-style "What Just Happened?" explainer.
- Scenario 1: DNS Security Policy blocks at resolver level (prevents C2, phishing).
- Scenario 2: Real-time policy updates without restart (SOC incident response).
- Scenario 3: DNS as universal telemetry source (detect exfiltration, lateral movement).
- Scenario 4: Layered threat intelligence (proactive blocking).
- Scenario 5: Correlation engine (DNS + TI + rules) → automated SOC alerting.
- Screenshot placeholders use emoji (💡, 📸) for scannability; language targets first-time users (no DNS/Sentinel expertise assumed).
- Consolidated into decisions.md 2026-05-04 entry.
- Created DEMO-GUIDE.md with step-by-step demo workflow and timing estimates
- Fixed Scenario 2 copy-paste commands in README (commands now executable end-to-end)
- Identified and corrected domain list references to match infra/main.bicep deployment

### 2026-05-04 — Team Decision Consolidation (P2 Wave)
- All P2 wave agent deliverables now consolidated into decisions.md via Scribe archival process.
- Mermaid diagram and Learning Resources table integration documented in Scribe records.

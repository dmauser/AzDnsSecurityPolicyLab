# DEMO-GUIDE: Azure DNS Security Policy Lab (45 min)

**Use this 5 minutes before going on stage. Scan top-to-bottom in 2 minutes.**

---

## ⏱ TIMING MAP (45 min total)

| Phase | Time | Activity |
|-------|------|----------|
| **Intro & Deploy** | 12–15 min | Explain architecture; deployment runs in background |
| **Scenario 1: DNS Blocking** | 5 min | Run `dig` from VM; show blockpolicy response |
| **Scenario 3: Monitoring** | 5 min | Show Log Analytics KQL query results |
| **Scenario 4: Threat Intel** | 8 min | Enable TI, run test script, show blocked list |
| **Scenario 5: Sentinel Detection** | 10 min | Show incidents, walk Analytics Rule logic |
| **Q&A Buffer** | 5 min | Questions, audience comments |

---

## 🎯 BEFORE YOU WALK ON STAGE

- [ ] Lab deployed 1+ hours ago (Sentinel needs time to ingest)
- [ ] `./scripts/pre-demo-check.sh` shows **all green**
- [ ] Browser tabs open: Azure Portal, Sentinel, Log Analytics, DNS Security Policy
- [ ] Terminal: Connected to VM via Bastion, verified `dig` installed
- [ ] Backup: Screenshot of dig output and KQL results saved locally

---

## 📋 PHASE-BY-PHASE DEMO SCRIPT

### PHASE 1: DNS Blocking Test

**🗣️ Say:**  
*"We're testing if our DNS policy blocks malicious domains. Watch what happens when we query a blocked domain—notice the response."*

**💻 Show:**  
On VM via Bastion:
```bash
dig malicious.contoso.com +short
# Expected: blank (no output = blocked)

dig google.com +short
# Expected: IP like 142.250.x.x
```

**✅ Expect:**  
- Blocked domain = **no output** or `blockpolicy.azuredns.invalid` NXDOMAIN
- Allowed domain = **actual IP address**

**⚠️ If it fails:**  
- If you see real IP for malicious domain: DNS policy hasn't propagated yet. Say: *"Policies take ~2 min. Let's check the monitoring side."* Switch to Log Analytics.
- If `dig` command not found: Run `sudo apt-get install dnsutils -y` first.

---

### PHASE 2: Log Analytics Monitoring

**🗣️ Say:**  
*"Every query—allowed and blocked—flows to Log Analytics. Let me show you the audit trail."*

**💻 Show:**  
In Azure Portal → Log Analytics Workspace → Logs:
```kusto
AzureDiagnostics 
| where ResourceType == "DNSRESOLVER_DNSQUERYEVENTS"
| where name_s has "malicious" or name_s has "exploit"
| project TimeGenerated, name_s, response_code_d, query_type_s
| summarize BlockCount=count() by name_s
```

**✅ Expect:**  
Table showing blocked domains with counts.

**⚠️ If no results:**  
- Say: *"Logs can lag 2–5 minutes. Here's a cached result…"* (show screenshot)
- Check Diagnostic Settings are enabled in the resource group.

---

### PHASE 3: Threat Intel Testing

**🗣️ Say:**  
*"Now let's test threat intelligence. We'll query 50 known malicious domains and see how many our policy blocks."*

**💻 Show:**  
On VM:
```bash
./scripts/dnstest.sh | tail -20
# Shows summary: X blocked, Y allowed
```

**✅ Expect:**  
Output showing ~80% of threat-intel-flagged domains blocked.

**⚠️ If it fails:**  
- If script not found: `curl -L https://raw.githubusercontent.com/dmauser/AzDnsSecurityPolicyLab/refs/heads/main/scripts/dnstest.sh -o dnstest.sh && chmod +x dnstest.sh`

---

### PHASE 4: Sentinel Detection

**🗣️ Say:**  
*"Sentinel automatically detects attack patterns from these DNS queries. Watch the incident appear in real-time."*

**💻 Show:**  
In Azure Portal → Microsoft Sentinel → Incidents:
- Show open incidents from Summary Rules
- Click one → show related Log Analytics data

**✅ Expect:**  
1–3 incidents visible; query volume spike correlates with threat domains.

**⚠️ If no incidents:**  
- Summary Rules run hourly. Say: *"The detection summary runs hourly. Here's what it would show…"* → Show Analytics Rule in content editor.

---

## 🔑 KEY TALKING POINTS (Emphasize these)

1. **Policy-as-Code**  
   *"Everything is Bicep. No click-ops. Reproducible. Version-controlled."*

2. **Cost: 80% Savings**  
   *"$9–12/month vs. $5,000+ for a traditional DNS firewall."*

3. **Layered Detection**  
   *"We correlate domain + parent domain + CNAME + IP. Multi-vector approach catches evasion."*

---

## 🆘 PANIC GUIDE

| Problem | Recovery (60 sec) |
|---------|-------------------|
| DNS not blocking | Verify policy linked to VNet: `az dns-resolver policy show -g $RG -n dns-security-policy-lab` |
| No logs in Log Analytics | Check Diagnostic Settings enabled. Logs lag 2–5 min. Show screenshot. |
| Sentinel no incidents | Summary Rule is hourly. Open Analytics Rule editor to show detection logic. |
| Bastion won't connect | Close tab. Go Portal → VM → Connect → Bastion again. Wait 2 min. |
| dig not installed | `sudo apt-get install dnsutils -y` |

---

## 💾 KEY COMMANDS (Copy-paste ready)

```bash
# Get resource group name
RG=$(jq -r '.resourceGroupName' answers.json)

# Test DNS blocking
dig malicious.contoso.com
dig exploit.adatum.com
dig google.com

# Run e2e test suite
./scripts/e2e-test.sh

# Verify lab health
./scripts/verify-lab.sh
```

---

**Status: Ready to present.** 🚀

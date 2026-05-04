# Azure DNS Security Policy Lab — Demo Readiness Review

**Prepared by:** Zeddemore (Docs/DevRel Specialist)  
**Date:** May 4, 2026  
**Scope:** README.md + scripts/ directory for demo/workshop presenter experience

---

## Executive Summary

The lab is **strong on content depth but weak on demo flow**. It reads like developer documentation rather than a presenter's script. A presenter would struggle to know:
- How long each step takes
- What exact output to expect on screen
- How to handle failures live
- What learnings to emphasize
- What the audience should do next

**Key finding:** The 5 scenarios are buried and scattered—there's no clear "start here for a 30-min demo" path.

---

## 1. README as a Presentation Guide ❌ **Needs Work**

### Current State
- README is **developer-focused**, not presenter-focused
- Jumps between setup, scenarios, troubleshooting without clear structure
- No "demo track" vs. "reference" delineation
- Scenarios (1-5) are documented but lack **flow narrative**

### Issues
- **No executive summary** for opening the demo ("What will you see?")
- **Scenarios scattered** across 250+ lines with KQL queries embedded mid-flow
- **No "demo timeline"** — presenter doesn't know if this is a 10-min or 90-min talk
- **Architecture diagram** exists but isn't tied to demo steps ("Here's what you'll build…")

### Recommendations (README edits + new file)

#### A. Create `DEMO_SCRIPT.md` (NEW FILE)
A **presentation-focused** guide separate from developer docs. Structure:

```markdown
# 30-Minute Azure DNS Security Demo Script

## 🎯 Demo Objectives (What audience learns)
- DNS security policies block malicious domains at Layer 3
- Azure DNS returns a custom response (blockpolicy.azuredns.invalid)
- Log Analytics captures every query for forensics
- Threat Intelligence + Sentinel = automated threat detection

## ⏱️ Timeline Breakdown
- Setup/Intro: 2 min
- Deploy: 12 min (run in background during intro)
- DNS blocking demo: 5 min
- Log Analytics deep-dive: 8 min
- Q&A: 3 min

## 📺 What You'll Show On Screen
[See section 3 below for detailed output examples]

## Step-by-Step Demo Flow
### Phase 1: Setup (while deploying in background)
[Clear speaker notes]

### Phase 2: Test DNS Blocking
[Copy-paste commands + expected output]

### Phase 3: Show Log Analytics
[Pre-baked queries, not live coding]
```

#### B. Restructure README
- Move scenarios to **"Demo Scenarios"** section at top, link them clearly
- Add **"⏱️ Timeline"** section under each scenario
- Add **"Expected Output"** subsections (see recommendation 3)
- Move advanced KQL to appendix or new file

---

## 2. Copy-Paste Readiness ✅ **Good, with caveats**

### Strengths
- Commands are clearly delimited in code blocks
- PowerShell and Bash variants provided
- Scripts handle subscriptions interactively ✅

### Issues

#### Issue 2a: Commands require editing before running
**Line 97-98** (Bash, Key Vault password retrieval):
```bash
az keyvault secret show --vault-name '<kv-name-from-output>' --name 'vm-admin-password' --query value -o tsv
```
- Requires manual replacement of `<kv-name-from-output>`
- Presenter must pause and edit while live

**Fix:** Provide a wrapper script or show how to capture output:
```bash
# Copy-paste ready version:
KV=$(az deployment group show -g rg-dns-security-lab -n main --query properties.outputs.keyVaultName.value -o tsv)
az keyvault secret show --vault-name "$KV" --name 'vm-admin-password' --query value -o tsv
```

#### Issue 2b: Scenario 4 dnstest.sh requires download
**Line 447:**
```bash
curl -L https://raw.githubusercontent.com/dmauser/AzDnsSecurityPolicyLab/refs/heads/main/scripts/dnstest.sh -o dnstest.sh
```
- URL is long, error-prone to type
- Better: Pre-download or create an **install script** that presenter runs once

#### Issue 2c: Scenario 5 Analytics Rule requires copy-pasting huge KQL blocks
- Multi-line KQL queries (lines 558-611) are impossible to copy live
- Solution: Provide as **copy-paste-ready JSON ARM template** with one-click deploy (already exists at line 549 ✅ but presenter may not notice)

### Recommendations (new file + README edits)

#### A. Create `scripts/demo-helper.sh` (NEW FILE)
Pre-deployment script that presenter runs once:
```bash
#!/bin/bash
# demo-helper.sh — Set up everything needed for a live demo

# 1. Download scripts and tools into demo directory
mkdir -p ~/demo
cd ~/demo
curl -L https://raw.githubusercontent.com/dmauser/AzDnsSecurityPolicyLab/refs/heads/main/scripts/dnstest.sh -o dnstest.sh
chmod +x dnstest.sh

# 2. Pre-create variable file for copy-paste commands
echo "# Run once after deployment and source this in your shell:"
echo "export RG='rg-dns-security-lab'"
echo "export KV=\$(az deployment group show -g \$RG -n main --query properties.outputs.keyVaultName.value -o tsv)"
echo "export VM_PASS=\$(az keyvault secret show --vault-name \$KV --name vm-admin-password --query value -o tsv)"
echo "export VM_NAME=\$(az deployment group show -g \$RG -n main --query properties.outputs.vmName.value -o tsv)"
```

#### B. Update README with "Copy-Paste Blocks"
Label sections with a **🔗 Copy-Paste Ready** emoji:
```markdown
### Quick Copy-Paste — Retrieve Password
🔗 **Copy-Paste Ready**

Open PowerShell and paste this entire block:
\`\`\`powershell
$RG = 'rg-dns-security-lab'
$KV = az deployment group show -g $RG -n main --query properties.outputs.keyVaultName.value -o tsv
Get-AzKeyVaultSecret -VaultName $KV -Name 'vm-admin-password' -AsPlainText
\`\`\`
```

---

## 3. Expected Output Examples ❌ **Critical Gap**

### Current State
- README says commands "should return blockpolicy.azuredns.invalid" but **never shows the actual output**
- KQL queries documented but **no sample result set shown**
- Presenter has no idea what success looks like on screen

### Missing Screenshots/Examples

#### Issue 3a: DNS blocking commands
**Expected:** Actual `dig` output
```
Current text: "Expected: blockpolicy.azuredns.invalid"
Needed: 
$ dig malicious.contoso.com

; <<>> DiG 9.18.0-ubuntu <<>> malicious.contoso.com
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, rcode: NOERROR, id: 12345
;; flags: qr aa rd ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;malicious.contoso.com.		IN	A

;; ANSWER SECTION:
malicious.contoso.com.	600	IN	A	1.2.3.4

;; Query time: 12 msec
;; SERVER: 168.63.129.16#53(168.63.129.16)
;; WHEN: Mon May 04 14:32:10 UTC 2026
;; MSG SIZE  rcvd: 50
```

#### Issue 3b: Log Analytics query results
**Expected:** A screenshot or table output showing:
- Query names (malicious.contoso.com, exploit.adatum.com)
- ResolverPolicyRuleAction = "Deny"
- Count of blocked queries
- Screenshot of Sentinel Incident creation

#### Issue 3c: Threat Intelligence results
Line 486 shows screenshot placeholder: `![DNS Threat Intelligence results in Log Analytics](media/DNSThreadIntel.png)` ✅  
But **no sample data** under "You should see results similar to this:"

### Recommendations (new file + README edits)

#### A. Create `docs/DEMO_OUTPUT_REFERENCE.md` (NEW FILE)
Contains every expected terminal output, screenshot description, and anomalies to look for:

```markdown
# Demo Output Reference — What You'll See

## Step 1: DNS Blocking Test
### Command
\`\`\`bash
dig malicious.contoso.com
\`\`\`

### Expected Output
[Full dig output here]

### What to point out to audience
- "Notice the SERVER line shows Azure DNS (168.63.129.16)"
- "The ANSWER returns blockpolicy.azuredns.invalid"
- "This happens **before** the malicious site is even contacted"

### If you see something else
- If you get an IP address: DNS policy not linked yet, wait 2-3 min
- If you get SERVFAIL: Bastion connectivity issue

---

## Step 3: Log Analytics Query
### Run this KQL query
\`\`\`kusto
DNSQueryLogs
| where ResolverPolicyRuleAction == "Deny"
| summarize count() by QueryName
| order by count_ desc
\`\`\`

### Expected Results
| QueryName | count_ |
|---|---|
| malicious.contoso.com. | 42 |
| exploit.adatum.com. | 38 |

### What to point out
- "80 blocked attempts in just 5 minutes of testing"
- "Each blocked query is logged for forensics"
```

#### B. Create `media/expected-outputs.txt` (NEW FILE)
Plain text versions of all expected outputs (for console sharing).

#### C. Update README
- Add **"🎬 Expected Output"** subsection under each scenario step
- Link to `DEMO_OUTPUT_REFERENCE.md` at top

---

## 4. Timing Guidance ⚠️ **Absent**

### Current State
- No timeline anywhere
- Deployment takes ~12 minutes but **README doesn't say so**
- Log Analytics queries take 2-5 minutes to appear but **not mentioned upfront**
- DNS propagation delays (2-3 min) mentioned in troubleshooting, not in main flow

### Issues
- Presenter doesn't know: "Is this a 15-min or 60-min demo?"
- No guidance on what to do **during the 12-min deploy wait**
- Audience doesn't know expectations ("Why are we waiting?")

### Recommendations (README edits)

#### A. Add timing to README introduction
```markdown
## ⏱️ Demo Duration Guide

Choose your demo length:

| Duration | Coverage | Scenario |
|---|---|---|
| **15 min** | DNS blocking basics | Scenario 1 only (pre-deploy) |
| **30 min** | DNS + monitoring | Scenarios 1-3 (pre-deploy first) |
| **60 min** | Full lab walk-through | All 5 scenarios + manual config |

**Note:** Deploy takes ~12 minutes. For live demos, pre-deploy to a separate session.
```

#### B. Add "What to do during deploy" section
```markdown
### During the 12-minute deployment...

**For presenters with live audience:**
1. Show architecture diagram (1 min)
2. Explain DNS security policy concept (3 min)
3. Walk through Bicep template (5 min)
4. Check: Is deployment done yet? [bash] ./scripts/verify-lab.sh [/bash]
5. If not ready, explain monitoring setup

**For recorded demos:** Deploy in advance, edit down waiting time.
```

#### C. Add timeline to each scenario
```markdown
### Scenario 1: Basic DNS Blocking Test ⏱️ 5 minutes

1. Connect via Bastion (1 min)
2. Run dig commands (2 min)
3. Verify results (2 min)

**Timeline note:** If you don't see blockpolicy.azuredns.invalid, wait 
2-3 minutes for DNS policy to propagate, then retry.
```

#### D. Create timing reference
In `DEMO_SCRIPT.md`:
```markdown
## Pre-Demo Checklist
- [ ] Run `./scripts/deploy-lab.sh` now (takes 12 min + 3 min for DNS to propagate)
- [ ] Verify with `./scripts/verify-lab.sh` (2 min)
- [ ] Pre-load Log Analytics queries
- [ ] Test Bastion connection
- [ ] Open all browser tabs in advance

**Time to ready:** ~20 minutes before going live
```

---

## 5. Troubleshooting Section — "Panic Guide" ✅ **Exists but needs demo-specific section**

### Current State
Troubleshooting section exists (lines 765-804) with good technical content:
- Permission denied ✅
- No subscriptions ✅
- DNS not blocking ✅
- Cannot access VM ✅

### Issues
- **Doesn't address live demo failures**
- **No "60-second fix" guidance** for common issues
- **No "ask for help" prompts** (when to give up and move on)

### Recommendations (README edit)

#### Add "Live Demo Troubleshooting" subsection
```markdown
## 🆘 Live Demo Troubleshooting — Quick Fixes

### "dig returns SERVFAIL"
**Status:** Bastion connectivity issue  
**60-second fix:** 
1. Close Bastion browser tab
2. Reconnect via Portal
3. Re-run dig

**If still broken:** Move to next section, show Log Analytics queries 
instead. Say: "Bastion sometimes needs a moment. Let me show you 
the monitoring side instead."

### "Log Analytics shows no results"
**Status:** Queries haven't appeared yet (normal)  
**Expected:** Logs appear 2-5 minutes after sending queries  
**Action:** 
- First time: "Let me query a pre-populated sample dataset..." 
  [switch to pre-demo queries]
- Say: "Live logging can be delayed; let's see what we captured earlier."

### "DNS not blocking (returns real IP)"
**Status:** Policy not yet linked OR policy not propagated  
**60-second fix:** Wait 3 minutes, retry.  
**What to say:** "DNS policies take a moment to activate. While we wait, 
let me show you the architecture..."

**Bail-out option:** Have a screenshot of successful output ready 
to show if timing doesn't work out.
```

---

## 6. Audience Takeaways ❌ **Not Explicit**

### Current State
- README teaches the **"how"** (deploy, query, test)
- Doesn't state the **"why"** or **"so what"** for audience
- No learning objectives upfront
- Audience walks away knowing steps, not concepts

### Issues
- Demo focuses on commands and tools
- Doesn't answer: "Why should I care about DNS security policies?"
- Doesn't make audience think: "I can use this for…"

### Recommendations (new file + README edits)

#### A. Create `LEARNING_OBJECTIVES.md` (NEW FILE)
Clear takeaways tied to job roles:

```markdown
# Learning Objectives — What You'll Understand After This Demo

## For Security Teams
✅ DNS policies block malicious domains **at the network layer** — 
   before an app or user can be infected  
✅ You get a **central record of all DNS queries** for forensics  
✅ You can create **rules in minutes** without buying a firewall  

## For Network Architects
✅ Implement **zero-trust DNS** for Azure VNets  
✅ Route DNS queries through **centralized policies** (DNS resolver)  
✅ No NSGs, no IDS/IPS complexity — just DNS rules  

## For Compliance Officers
✅ Audit trail of **every blocked domain attempt**  
✅ Export logs to SIEM for **compliance dashboards**  
✅ Cost-effective threat detection (**~$10/month** vs $1000+ for appliances)  

## For Cloud Engineers
✅ Bicep Infrastructure-as-Code for **repeatable deployments**  
✅ Auto-logging to Log Analytics for **proactive monitoring**  
✅ Integrate Sentinel for **automated threat response**  
```

#### B. Update README with "Key Takeaways" section
Add after scenarios:
```markdown
## 🎓 Key Learning Points

After this lab, you understand:

1. **DNS as a security boundary** — Block before users reach the site
2. **Observability by default** — Every query logged automatically
3. **Zero-trust architecture** — No device can bypass DNS policy
4. **Cloud-native threat intel** — Sentinel detects threats automatically
5. **Cost-effective security** — $9/month for full VNet protection
```

#### C. Add takeaway callouts during demo
In `DEMO_SCRIPT.md`:
```markdown
### [PRESENTER NOTE - Emphasize This Point]
"Notice what didn't happen here — we didn't need:
- A firewall appliance ($5K+)
- A dedicated DNS admin
- Manual rule updates
- Complex IP whitelisting

One DNS policy, automatic updates, centralized logs."
```

---

## 7. Call-to-Action — "What Next?" ⚠️ **Weak**

### Current State
- README ends with "Contributing" section (customization suggestions)
- Doesn't direct audience to **next concrete actions**
- No pathway from lab → production-ready policy

### Issues
- **No "deploy this in your environment" call-to-action**
- **No "extend the lab" ideas** for different scenarios
- **No "share your results" encouragement** (GitHub issues, blog post)
- Audience leaves without a mission

### Recommendations (new file + README edit)

#### A. Create `NEXT_STEPS.md` (NEW FILE)
Clear post-demo actions:

```markdown
# 🚀 Next Steps After the Demo

## Option 1: Deploy to Your Environment (30 min)
- [ ] Fork this repo
- [ ] Update `infra/main.bicepparam` with your domain names
- [ ] Update `answers.json` with your resource group
- [ ] Run `./scripts/deploy-lab.sh`
- [ ] Link the policy to your production VNet
- [ ] Tweet: "Just deployed Azure DNS Security Policy with 
        @dmauser AzDnsSecurityPolicyLab!"

## Option 2: Extend the Lab (60 min)
- [ ] Add your organization's custom domain blocklist
- [ ] Set up Slack alerts when threats are detected
- [ ] Create Power BI dashboard for DNS security metrics
- [ ] Integrate with your existing SIEM

## Option 3: Report Your Results (15 min)
- [ ] GitHub issue: "I deployed this in [YOUR_ENVIRONMENT]"
- [ ] LinkedIn post: How you're protecting your VNets
- [ ] Internal demo: Show your security team

## Option 4: Deep Dive (120 min)
- [ ] Scenario 5: Set up Sentinel analytics rules (already in the lab)
- [ ] Create a custom threat intelligence feed
- [ ] Implement multi-policy patterns (different rules per subnet)
```

#### B. Add "Try at Home" section to README
```markdown
## 💡 Try It Yourself

After the demo:

1. **Deploy this in your subscription** 
   Fork → customize → run `./scripts/deploy-lab.sh`
   (~15 minutes to production DNS security)

2. **Add your own malicious domain list**
   Edit `infra/main.bicep` to add custom blocklist
   
3. **Create Sentinel alerts**
   Use Scenario 5 as a starting point for your org's threat model

4. **Share your setup**
   GitHub issue: "I deployed this for [YOUR_USE_CASE]"
   We'd love to hear how you adapted it!
```

#### C. Add "Quick Links" footer
```markdown
## 🔗 Quick Links
- [Deploy Now](#🚀-quick-start)
- [Next Steps](./NEXT_STEPS.md)
- [Learning Objectives](./LEARNING_OBJECTIVES.md)
- [Full Demo Script](./DEMO_SCRIPT.md)
- [GitHub Issues - Feature Requests](https://github.com/dmauser/AzDnsSecurityPolicyLab/issues)
```

---

## 📋 Summary of Recommendations

| # | Category | Recommendation | Type | Effort | Impact |
|---|---|---|---|---|---|
| 1.1 | Presentation Flow | Create `DEMO_SCRIPT.md` with structured speaker notes | New file | **Medium** | **High** |
| 1.2 | README Structure | Restructure scenarios at top with timeline | README edit | Low | High |
| 2.1 | Copy-Paste Ready | Create `scripts/demo-helper.sh` | New script | Low | High |
| 2.2 | Copy-Paste Ready | Label copy-paste blocks in README with 🔗 | README edit | Low | Medium |
| 3.1 | Expected Outputs | Create `docs/DEMO_OUTPUT_REFERENCE.md` | New file | **High** | **High** |
| 3.2 | Expected Outputs | Create `media/expected-outputs.txt` | New file | Low | Medium |
| 4.1 | Timing | Add ⏱️ timeline sections to README | README edit | Low | **High** |
| 4.2 | Timing | Add "What to do during deploy" section | README edit | Low | Medium |
| 5.1 | Panic Guide | Add "Live Demo Troubleshooting" to troubleshooting section | README edit | Low | **High** |
| 6.1 | Takeaways | Create `LEARNING_OBJECTIVES.md` | New file | Low | High |
| 6.2 | Takeaways | Add "Key Learning Points" to README | README edit | Low | Medium |
| 7.1 | Call-to-Action | Create `NEXT_STEPS.md` | New file | Low | **High** |
| 7.2 | Call-to-Action | Add "Try at Home" section to README | README edit | Low | Medium |

---

## 🎯 Quick Priority Ranking

**Do First (enables live demo):**
1. Create `DEMO_SCRIPT.md` — structured presenter flow
2. Create `docs/DEMO_OUTPUT_REFERENCE.md` — know what you're looking for
3. Create `scripts/demo-helper.sh` — copy-paste ready downloads

**Do Second (better audience experience):**
4. Add timing guidance to README
5. Create `LEARNING_OBJECTIVES.md` — clear takeaways
6. Add "Live Demo Troubleshooting" section

**Do Third (follow-up engagement):**
7. Create `NEXT_STEPS.md` — audience action path
8. Add "Try at Home" section

---

## Appendix: File Checklist

- ✅ `README.md` — Restructure existing
- 📝 `DEMO_SCRIPT.md` — NEW, ~300 lines
- 📝 `docs/DEMO_OUTPUT_REFERENCE.md` — NEW, ~200 lines
- 📝 `LEARNING_OBJECTIVES.md` — NEW, ~60 lines
- 📝 `NEXT_STEPS.md` — NEW, ~80 lines
- 📝 `scripts/demo-helper.sh` — NEW, ~40 lines
- 📝 `media/expected-outputs.txt` — NEW, ~150 lines (optional)

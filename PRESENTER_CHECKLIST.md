# Presenter's Quick Checklist — Before Your Demo

Use this **5 minutes before going live** to verify everything.

---

## ✅ Pre-Demo Setup (Do this 20 minutes early)

### Environment Ready
- [ ] Run `./scripts/deploy-lab.sh` **now** (takes 12 min)
- [ ] Verify with `./scripts/verify-lab.sh` (confirms all resources created)
- [ ] Record the Key Vault name and VM password
  ```bash
  KV=$(az deployment group show -g rg-dns-security-lab -n main --query properties.outputs.keyVaultName.value -o tsv)
  az keyvault secret show --vault-name "$KV" --name vm-admin-password --query value -o tsv
  ```

### Browser Tabs (open these in advance)
- [ ] Azure Portal (https://portal.azure.com)
- [ ] Your VM in Portal → Connect → Bastion ready to click
- [ ] Log Analytics workspace → Logs tab
- [ ] Microsoft Sentinel (if doing Scenario 5)

### Terminal Ready
- [ ] Bash or PowerShell session open
- [ ] Changed to repo directory: `cd AzDnsSecurityPolicyLab`
- [ ] Pre-load environment variables (see demo-helper.sh output)

### Backup Plans
- [ ] Screenshot of successful dig output ready (if Bastion fails)
- [ ] Screenshot of Log Analytics results ready (if logging is slow)
- [ ] Have a link to this repo visible in case you need to reference docs

---

## ⏱️ Demo Timeline (30-minute version)

| Time | What You Do | What Audience Sees | Notes |
|------|---|---|---|
| 0:00-1:00 | **Intro** | Architecture diagram | Explain VNet → DNS Policy → Bastion |
| 1:00-2:00 | **Concepts** | Show README scenarios | "We're doing scenario 1 today" |
| 2:00-4:00 | **Setup** | Verify deployment complete | Show `verify-lab.sh` output |
| 4:00-7:00 | **Access VM** | Bastion browser SSH terminal | "No public IP, browser access only" |
| 7:00-12:00 | **DNS Blocking** | `dig malicious.contoso.com` results | "Notice the blockpolicy response" |
| 12:00-15:00 | **Monitoring** | Log Analytics query results | Show blocked vs. allowed query counts |
| 15:00-25:00 | **Deep Dive** | KQL queries, threat patterns | "This is what a 5-minute attack looks like" |
| 25:00-30:00 | **Takeaways + Q&A** | Summary slide, next steps link | Point to NEXT_STEPS.md |

---

## 🚨 Common Failures & Recovery

### "Bastion browser connection times out"
**Recovery (60 seconds):**
1. Close the browser tab
2. Go back to Portal → Virtual Machines → Your VM
3. Click Connect → Connect via Bastion again
4. Wait for loading (usually 2 min after deploy)

**If still broken:** Say "Sometimes Bastion needs a moment—let me show you the monitoring side instead" and jump to Log Analytics query.

### "dig returns a real IP instead of blockpolicy"
**Recovery (Wait then retry):**
1. This means DNS policy isn't propagated yet
2. Say: "DNS policies take a moment to activate. While we wait, let me explain…"
3. Wait 3 minutes, then retry
4. If still broken, show the screenshot you prepared

### "Log Analytics shows no results"
**Recovery (Show pre-loaded data):**
1. Say: "Logs can be delayed 2-5 minutes. Let me show you a pre-populated dataset…"
2. Switch to pre-demo queries with sample data
3. Or say: "In production, we'd see similar patterns. Here's what the volume looks like…"

### "Copy-paste command fails"
**Recovery (Slow down):**
1. Don't worry—demo isn't about speed, it's about understanding
2. Slow type the command so audience sees it building
3. Explain what each flag does

---

## 📋 What Audience Should Walk Away With

**Point out these 3 things during the demo:**

1. **DNS is a security boundary**
   - "We're blocking here, before the malicious site ever gets contacted"
   - Point to: blockpolicy response

2. **Everything is logged**
   - "Every query—allowed and blocked—goes to Log Analytics"
   - Point to: Query count in Log Analytics

3. **It's cost-effective**
   - "This entire lab costs ~$9-12/month to run"
   - "A traditional firewall would cost $5,000+"

---

## 🎁 What to Leave Them With

Before ending, show them:
- [ ] Link to this repo (in chat, on screen, or handout)
- [ ] Link to `NEXT_STEPS.md` (tell them what to do next)
- [ ] Invite to GitHub issues for questions/ideas
- [ ] If recording: link to recording + slides

Suggested words:
> "You can deploy this in your own Azure environment in about 20 minutes.
> Here's the repo. Here are your next steps. We'd love to hear how you 
> adapted it for your organization!"

---

## 🔗 Key Files to Reference

- **README.md** — Full documentation
- **DEMO_SCRIPT.md** — Detailed presenter notes (when available)
- **DEMO_OUTPUT_REFERENCE.md** — What you'll see on screen (when available)
- **NEXT_STEPS.md** — What audience should do after (when available)
- **LEARNING_OBJECTIVES.md** — Key concepts by role (when available)

---

## 💡 Pro Tips

1. **Pre-demo check (5 min before):**
   ```bash
   ./scripts/verify-lab.sh && echo "✅ Everything ready!"
   ```

2. **If something breaks:**
   - You have 60 seconds to fix it
   - If not fixed, pivot to the backup screenshots
   - Don't apologize—just move forward

3. **Show, don't tell:**
   - Let audiences see the actual dig output
   - Let them see actual Log Analytics results
   - Point out what's interesting (the blockpolicy response, the query count)

4. **Engagement questions:**
   - "What would happen if we didn't have this policy?"
   - "How would you extend this to your organization?"
   - "What other domains would you block?"

5. **Recording tip:**
   - Record at 2x speed if you demo is going slow (edit later)
   - Cut the 12-minute deploy time—jump to "resources created"
   - Show expected outputs if live demo doesn't cooperate

---

## 📞 Still Stuck?

- Check the **Troubleshooting** section in README.md
- Check **DEMO_READINESS_REPORT.md** for detailed guidance
- Create a GitHub issue: "Demo issue: [problem]"

---

**Good luck! 🚀**

# Brave Group Policy Enforcement Setup - Windows 11 Pro

**Status:** Superseded for the ADMX route; the registry route is live.

The ADMX/ADML procedure below was **never deployed** — no `brave*.admx` is
installed in `C:\Windows\PolicyDefinitions`. Brave policy on this host is
enforced by the registry, applied by `Set-BraveMachinePolicy.ps1` in this
folder, whose in-force `HKLM` values were verified to match the script exactly.

Keep this document as the reference for what each policy means and how to
verify it with `gpresult` / `chrome://policy`. Do not follow Phase 2 (the ADMX
copy) unless you are deliberately switching enforcement routes. See
`README.md` in this folder for the current applied/unapplied status of each
script.

---

## Overview

This document guides you through enforcing Brave browser settings across all user accounts on your Windows 11 Pro machine using Group Policy. After completing these steps, you must reboot for policies to take effect.

---

## Phase 1: Prepare Admin Settings (Before Group Policy Setup)

1. Log in to your **Administrator account**
2. Open Brave and configure the settings you want to enforce:
   - Homepage URL
   - Default search engine
   - Extensions (which to allow/block)
   - Sync settings
   - Privacy settings
   - Proxy configuration (if applicable)
3. **Note down or screenshot** the exact settings you configured

---

## Phase 2: Download Brave Policy Templates

Brave's Group Policy support requires administrative templates (ADMX/ADML files).

1. Go to: https://github.com/brave/brave-browser/releases
2. Download the latest:
   - `brave_admin_template.admx`
   - `brave_admin_template.adml` (usually in a language folder like `en-US`)
3. Save these files temporarily on your desktop or Downloads folder

---

## Phase 3: Install Policy Templates

1. **Copy ADMX file:**
   ```
   Copy downloaded brave_admin_template.admx 
   To: C:\Windows\PolicyDefinitions\
   ```

2. **Copy ADML file:**
   ```
   Copy downloaded brave_admin_template.adml 
   To: C:\Windows\PolicyDefinitions\en-US\
   ```

3. If folders don't exist, create them first

---

## Phase 4: Access Group Policy Editor

1. Press `Win + R`
2. Type: `gpedit.msc`
3. Press Enter
4. Navigate to:
   ```
   Computer Configuration 
   → Administrative Templates 
   → BraveSoftware 
   → Brave
   ```

If you don't see "BraveSoftware", the templates weren't installed correctly. Go back to Phase 3.

---

## Phase 5: Configure Brave Policies

In the Brave folder, you'll see available policies. Common ones to enforce:

### Homepage
- Find: **Homepage URL**
- Set to: Your desired homepage

### Search Engine
- Find: **Default search provider**
- Set to: Your preferred search engine

### Extensions
- Find: **Extension allow/block list** or **Force installed extensions**
- Configure as needed

### Security/Privacy
- **Safe browsing** — Enforce protection level
- **Third-party cookies** — Block or allow
- **Sync** — Enable/disable sync capability

### Proxy Settings
- Find: **Proxy settings**
- Set if your network requires it

**For each policy you want to enforce:**
1. Double-click the policy name
2. Select: **Enabled**
3. Configure any additional settings in the options box
4. Click OK

---

## Phase 6: Apply Policies (Before Reboot)

Open PowerShell as Administrator and run:

```powershell
gpupdate /force
```

This refreshes Group Policy without needing a reboot yet.

---

## Phase 7: Verify Policies Are Configured

Still in PowerShell (as Administrator), run:

```powershell
gpresult /h "C:\Users\$env:USERNAME\Desktop\PolicyReport.html"
```

Open the generated HTML file and search for "BraveSoftware" to verify policies are listed.

---

## Phase 8: Test (Optional, Before Reboot)

1. Open Brave on your admin account
2. Try to change a setting you locked (e.g., homepage)
3. It should be grayed out or revert when you close Brave
4. If not locked, go back to gpedit and verify the policy is set to "Enabled"

---

## 🔄 AFTER REBOOT - CRITICAL STEPS

**You must reboot for Group Policy to apply to all user accounts.**

After rebooting:

1. **Test on each user account:**
   - Log in to each regular user account
   - Open Brave
   - Verify settings are locked/enforced
   - Try to change a policy setting (should fail or revert)

2. **Verify policies are active:**
   ```powershell
   # Run as Administrator on the user account
   gpresult /h report.html
   ```

3. **If policies don't appear enforced:**
   - Ensure you rebooted (not just restarted Brave)
   - Check that templates were copied to correct folders
   - Re-run: `gpupdate /force` and reboot again

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "BraveSoftware" not in Group Policy | Copy ADMX/ADML files to C:\Windows\PolicyDefinitions\ and reboot |
| Settings not enforced after reboot | Run `gpupdate /force` again, then reboot |
| Policies appear but aren't enforcing | Verify policy is set to "Enabled" (not "Disabled" or empty) |
| Brave is outdated | Policies work best on current Brave versions; update Brave |

---

## Quick Reference - Template File Locations

```
ADMX File:  C:\Windows\PolicyDefinitions\brave_admin_template.admx
ADML File:  C:\Windows\PolicyDefinitions\en-US\brave_admin_template.adml
Group Policy Editor: gpedit.msc
```

---

## Next Steps After Setup Verification

- [ ] Download Brave policy templates
- [ ] Install templates to PolicyDefinitions folder
- [ ] Open gpedit.msc and configure policies
- [ ] Run `gpupdate /force`
- [ ] **REBOOT COMPUTER** ⬅️ REQUIRED
- [ ] Test on user accounts
- [ ] Verify with `gpresult /h`
- [ ] Document which policies were enforced

---

**Document created:** 2026-08-11  
**Windows version:** Windows 11 Pro  
**Target browser:** Brave  

**⚠️ Remember: Reboot is required for policies to take effect on all user accounts.**

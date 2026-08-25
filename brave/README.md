# Brave browser policy

Brave enforcement for the Windows 11 Pro build host, homed here (BI-9) from the
unversioned `bonkey-apps` root. Brave policy is the Infra manager's remit
(ADR-0003), the same remit as the Pi-hole lists next door.

These are **not** Pi-hole lists. Nothing here is subscribed by URL, and merging
a change here deploys nothing to the box — it changes the *host*, and only when
someone runs the script.

## What is here, and whether it is actually in force

| File | Status | What it does |
|---|---|---|
| `Set-BraveMachinePolicy.ps1` | **APPLIED — live, verified** | Machine-wide `HKLM` Brave policy. The source of truth. |
| `Set-BraveUserDownloadPolicy.ps1` | **UNAPPLIED INTENT** | Per-user `HKCU` download-folder policy for standard accounts. |
| `Register-BraveUserDownloadTask.ps1` | **UNAPPLIED INTENT** | Registers a logon task to run the script above. |
| `BraveGroupPolicy_Setup.md` | **Reference only — ADMX route never deployed** | Explains each policy and how to verify it. |

### `Set-BraveMachinePolicy.ps1` — applied

Verified against the live registry on 2026-08-24. The in-force values under
`HKLM\SOFTWARE\Policies\BraveSoftware\Brave` match the script:

```
DefaultSearchProviderName      = DuckDuckGo
DefaultSearchProviderKeyword   = duckduckgo.com
DefaultSearchProviderEnabled   = 1
HomepageLocation               = https://html.duckduckgo.com/html
HomepageIsNewTabPage           = 0
RestoreOnStartup               = 4
BraveRewardsDisabled           = 1
BraveWalletDisabled            = 1
BraveVPNDisabled               = 1
DefaultBraveAdblockSetting     = 2   (aggressive)
DefaultBraveHttpsUpgradeSetting = 2
DefaultBraveFingerprintingV2Setting = 3
```

This is the enforcement route in use. If Brave policy needs changing, change
this script and re-run it elevated — do not hand-edit the registry, and do not
switch to the ADMX route described in `BraveGroupPolicy_Setup.md`.

Verify from the browser at `brave://policy`, or:

```powershell
Get-Item 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' |
  ForEach-Object { $k=$_; $k.GetValueNames() | ForEach-Object { "$_ = $($k.GetValue($_))" } }
```

### `Set-BraveUserDownloadPolicy.ps1` — unapplied intent

Intended to force standard (non-administrator) accounts to download into
`C:\Users\Public\Download`, leaving admin accounts on their per-profile
Downloads folder. It writes `HKCU`, so it must run **in the target user's own
context**, not as SYSTEM and not elevated-as-someone-else.

**Not in force.** No `HKCU\Software\Policies\BraveSoftware\Brave` key exists.

One honest caveat about that check: it was run from `famla`, which **is** a
local Administrator, and the script deliberately no-ops for administrators. So
the absence of the key under `famla` is exactly what a correct run would also
produce. What settles it is the next row — nothing schedules this script for
the standard accounts (`Abigail`, `Daniel`, `Timothy`), so it has never run in
their context either. To confirm for a given account, check that account's own
hive while logged in as them.

### `Register-BraveUserDownloadTask.ps1` — unapplied intent

Registers a per-user scheduled task to run `Set-BraveUserDownloadPolicy.ps1` at
every logon.

**Not in force.** `Get-ScheduledTask -TaskName '*Brave*'` returns nothing on
this host. No such task exists for any account.

Applying the download policy properly means running this registration once in
each standard account's context — an owner decision, not done here.

### `BraveGroupPolicy_Setup.md` — reference only

Documents the ADMX/ADML Group Policy route. That route was **never deployed**:
no `brave*.admx` is installed in `C:\Windows\PolicyDefinitions`. The document
stays because its per-policy explanations and its `gpresult` /
`brave://policy` verification steps are still the best reference we have. Its
Phase 2 (copy ADMX into PolicyDefinitions) should not be followed unless
someone deliberately decides to switch enforcement routes.

The Brave ADMX bundle is not committed here — it is a ~6 MB zip that expands to
~64 MB. Every Brave release ships its own `policy_templates.zip`; fetch the one
matching the installed Brave version from Brave's release assets if the ADMX
route is ever revived.

## Related

- `../provision/` — the Pi-hole VM rebuild scripts, and the Hyper-V enablement
  that is their prerequisite.
- `../docs/archive/` — superseded Docker-lane documents. Do not follow them.

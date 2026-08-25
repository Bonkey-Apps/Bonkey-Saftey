# Hyper-V Virtualization Repair Status Report

**Generated:** 2026-08-11 21:42:00  
**System:** Windows 11 Pro (Build 26200)  
**Processor:** Intel Core Ultra 9 275HX (24 cores)  
**RAM:** 32 GB

---

## Executive Summary

The Hyper-V hypervisor IS running successfully on your system, but the **Hyper-V management services are not installed**. This explains why virtualization features keep failing:

- ✅ Hypervisor: Running
- ✅ Virtualization-Based Security: Running
- ❌ Hyper-V Management Services: **NOT INSTALLED**

---

## Current Status

### Services Found on System

**Running:**
- CoworkVMService (running)
- NdisVirtualBus (running)

**Stopped (Guest Integration Services):**
- vmicguestinterface
- vmicheartbeat
- vmickvpexchange
- vmicrdv
- vmicshutdown
- vmictimesync
- vmicvmsession
- vmicvss

**NOT FOUND (Missing):**
- vmms (Hyper-V Virtual Machine Management Service) ❌
- nvspwmi (Nested Network Virtualization Service) ❌
- vmsp (VM Shielding Provider Service) ❌

### Recent Event Log Errors

All errors are from the same missing services:

```
[08/11/2026 21:16:42] Event ID 7000
The Nested Network Virtualization service failed to start due to the following error:
A hypervisor feature is not available to the user.

[08/11/2026 21:16:36] Event ID 7000
The VMSP service failed to start due to the following error:
Insufficient system resources exist to complete the requested service.
```

---

## Root Cause Analysis

The error **"A hypervisor feature is not available to the user"** means:

1. The Hyper-V hypervisor kernel component IS installed and running
2. BUT the Hyper-V **management services** (vmms, nvspwmi) are missing
3. Windows is trying to start these services at boot, but they don't exist
4. This prevents other features from being exposed to user applications

**Why this happens:**
- Hyper-V might be partially installed
- Management components were uninstalled or corrupted
- Windows feature registration is out of sync with actual installed files

---

## What to Try Next

### Option 1: Complete Hyper-V Reinstallation (Recommended)

This requires **two reboots** but will fully fix the issue:

```powershell
# Run as Administrator in PowerShell

# Step 1: Disable Hyper-V completely
dism /online /disable-feature /featurename:Microsoft-Hyper-V-All /all /norestart

# Reboot
shutdown /r /t 30 /c "Disabling Hyper-V for repair"
```

After reboot:

```powershell
# Step 2: Enable Hyper-V
dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart

# Reboot
shutdown /r /t 30 /c "Re-enabling Hyper-V repair"
```

### Option 2: Repair Windows Component Store

If Option 1 fails:

```powershell
# Run as Administrator
# Scan for corruption
sfc /scannow

# After it completes, if issues found:
DISM /Online /Cleanup-Image /RestoreHealth
```

### Option 3: Check Windows Features GUI

1. Open **Settings** → **Apps** → **Apps & features**
2. Click **"Optional features"**
3. Search for **"Hyper-V"**
4. If you see it, click **"Uninstall"**, restart
5. Then **"Add a feature"** and select **"Hyper-V"**, restart

---

## Next Steps

1. **Try Option 1 first** - it's the most direct fix
2. If it fails, collect the full output of each command
3. If Options 1-3 don't work, the system may need a Windows repair/reset

---

## Files Created for This Session

- Hyper-V-Repair.ps1 (Full disable/enable script with auto-reboot handling)
- Hyper-V-Service-Repair.ps1 (Service restart script - already ran)
- This status report: HYPER-V-REPAIR-STATUS.md

---

## Important Notes

- ⚠️ All fixes require **Administrator privileges**
- ⚠️ Options 1 will require **system reboots**
- ⚠️ Your system is currently **safe** - just missing management components
- ✓ The hypervisor itself is healthy and running

Let me know which option you'd like to try, and I can guide you through it!

---

## Update — 2026-08-12 Follow-up Session

### Diagnostics run

- `dism /online /get-features /format=table | findstr /i hyper` → **all Hyper-V features reported Disabled** (Microsoft-Hyper-V-All, Microsoft-Hyper-V, -Hypervisor, -Services, -Tools-All, -Management-PowerShell, -Management-Clients, HyperV-KernelInt-VirtualDevice, HyperV-Guest-KernelInt, HypervisorPlatform). This contradicts the "hypervisor IS running" conclusion in the original report above — the actual Hyper-V Windows feature was off.
- `Get-WmiObject Win32_Processor | Select VirtualizationFirmwareEnabled` → returned **False**. User confirmed via BIOS and Intel's own utility that VT-x **is** enabled in firmware — this WMI property is stale/unreliable on this build and should not be trusted going forward.
- `systeminfo | findstr /i "Hyper-V Virtualization Secure DEP SLAT"` → confirmed "Virtualization-based security: Running" and "A hypervisor has been detected," consistent with VT-x actually being active at the hardware level (VBS's own minimal hypervisor).
- `Get-Service vmms, nvspwmi, vmsp, WMI, WinRM` → only WinRM (Stopped/Manual) resolved; vmms/nvspwmi/vmsp/WMI didn't exist as services, consistent with the Hyper-V feature being disabled rather than installed-but-broken.

### Root cause (revised)

Not a BIOS/firmware issue. The `Microsoft-Hyper-V-All` Windows optional feature was simply **disabled**, so none of the management services (vmms, nvspwmi, vmsp) were registered. VT-x itself was fine the whole time.

### Action taken

Ran: `dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart`

Result: **Operation completed successfully.** DISM returned the reboot-required exit code (expected, since `/norestart` was passed). Hyper-V feature is enabled but **not yet active — a system reboot is required to complete installation.**

### Status: ⏳ Reboot pending

Next step: reboot the system, then verify with:
```powershell
dism /online /get-features /format=table | findstr /i hyper
Get-Service vmms, nvspwmi, vmsp, WMI -ErrorAction SilentlyContinue
```
Expect all Hyper-V features to show Enabled and vmms/nvspwmi/vmsp services to exist and start automatically.

---

## Update — Post-Reboot Verification: ✅ RESOLVED

After reboot, verification confirmed the fix worked:

- `dism /online /get-features` → `Microsoft-Hyper-V-All`, `-Hyper-V`, `-Tools-All`, `-Management-PowerShell`, `-Hypervisor`, `-Services`, `-Management-Clients` all **Enabled**. (`HypervisorPlatform` and the two `HyperV-KernelInt-*` features remain Disabled — these are separate optional sub-features, not required for standard Hyper-V use, and were not part of the original problem.)
- `vmms` (Hyper-V Virtual Machine Management Service) → **Running / Automatic**
- `vmsp` (VM Shielding Provider) → **Running / Automatic**
- `Winmgmt` (WMI, the actual service name — `nvspwmi` was never a real service on this build) → **Running**
- No new Event ID 7000 errors in the Hyper-V event logs
- `Get-VMHost` returned host info successfully; `Get-VM` cmdlet is available

**Hyper-V is fully operational.** Root cause was the `Microsoft-Hyper-V-All` Windows feature being disabled — not a BIOS/firmware issue, and not corrupted management services as originally suspected.

---

## Update — Docker Prerequisite Gap Found

Moving on to the Pi-hole-in-Docker deployment (see `QUICK_START.md`). Two issues found:

1. **`INSTALL_DOCKER.ps1` and `DEPLOY_PIHOLE.ps1` had a BOM-less encoding bug** — both scripts contain UTF-8 checkmark characters (✓/✗) with no byte-order-mark, which caused Windows PowerShell 5.1 to misread the file using the legacy ANSI codepage and throw `Unexpected token '}'` parse errors. Fixed by re-saving both files as UTF-8 with BOM (content unchanged).
2. **`VirtualMachinePlatform` feature was not enabled** — `INSTALL_DOCKER.ps1`'s prereq check requires it in addition to `Microsoft-Hyper-V-All`. Enabled directly via `Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform, Containers -NoRestart` (skipped `ContainersImage-oci` — not a valid feature name on this Windows build, and not required). **Reboot required to activate.**

### Status: ⏳ Reboot pending (again) before Docker install can proceed

---

## Update — Docker Install Attempt Failed: Missing WSL

After the reboot, `INSTALL_DOCKER.ps1` ran successfully (prereqs passed, download succeeded) but the actual Docker Desktop installer failed with exit code `-5` (`4294967291` unsigned). Installer log (`%LOCALAPPDATA%\Docker\log\host\DockerDesktopInstaller.exe.log`) showed the failure but no root cause; no Windows Event Log crash entries were found either.

Root cause found by checking `wsl --status`: **the Windows Subsystem for Linux feature itself (`Microsoft-Windows-Subsystem-Linux`) was Disabled.** `VirtualMachinePlatform` and `Containers` being enabled isn't sufficient — Docker Desktop's `--backend=wsl2` install explicitly needs the WSL feature too, which was never enabled by `ENABLE_HYPERV.ps1` (it only enables Hyper-V/VMP/Containers, not WSL).

Fixed via: `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart`. **Reboot required (again).**

### Status: ⏳ Reboot pending — after this one, Docker install should have all prerequisites (Hyper-V, VirtualMachinePlatform, Containers, WSL)

### Parallel track: Pi-hole native VM

Decided against running Pi-hole via Docker (see conversation) — needs to persist across reboots regardless of which Windows user (including non-admin) logs in, and Docker Desktop's backend is tied to a logged-in user session. Instead: Docker Desktop is being installed for general use only; Pi-hole will run natively inside a dedicated minimal Debian Hyper-V VM with "Automatic Start Action: Always start" (independent of user login, since `vmms` is a SYSTEM-level service).

Progress so far:
- `qemu-img` installed via `winget install cloudbase.qemu-img` (for qcow2→VHDX conversion) — binary at `%LOCALAPPDATA%\Microsoft\WinGet\Packages\cloudbase.qemu-img_Microsoft.Winget.Source_8wekyb3d8bbwe\qemu-img.exe`
- Downloading Debian 12 "generic" (not "genericcloud" — more likely to include Hyper-V drivers) qcow2 cloud image to `pihole-vm\debian-12-generic-amd64.qcow2`
- Plan: convert to VHDX, create Gen2 VM (Secure Boot disabled) on the existing "Default Switch" (NAT, local-machine-only per user preference), boot with a cloud-init NoCloud seed ISO (built via PowerShell IMAPI2, no extra tools) for SSH access + static network config
- Pi-hole itself will be installed *after* the VM is confirmed booting/SSH-reachable — not pre-baked into cloud-init — because Pi-hole v6's unattended install needs a pre-seeded `pihole.toml` whose exact current schema wasn't confirmed by research; safer to inspect it live on the VM than risk the installer hanging on an interactive ncurses prompt with no console access

---

## Update — Pi-hole VM: Base OS Working (after fixing 2 real bugs)

VM created: `pihole-vm`, Gen2, 1 vCPU, dynamic memory 512MB–1GB (768MB startup), Secure Boot off, "Default Switch" (NAT), `AutomaticStartAction: Start` (so it boots at Windows startup independent of user login, per the earlier design decision to avoid Docker Desktop's login-session dependency).

**Two real bugs found and fixed while debugging why cloud-init wasn't applying:**

1. **VM first booted to a stock `localhost login:` prompt** — hostname/user/network from cloud-init never applied. Diagnosed by capturing a screenshot of the VM's video framebuffer via `Msvm_VirtualSystemManagementService.GetVirtualSystemThumbnailImage` (WMI/CIM) converted to PNG — this is the way to see a headless Gen2 VM's console output without VMConnect. Serial console (`Set-VMComPort` to a named pipe) was tried first but produced no output — this Debian image apparently doesn't default to a serial getty.
2. **Root cause**: the cloud-init seed ISO I built via PowerShell's `IMAPI2FS.MsftFileSystemImage` COM object used `FileSystemsToCreate = 4`, which is the **UDF** flag, not ISO9660 (`1`) as intended — cloud-init's NoCloud datasource only scans `iso9660`/`vfat` volumes, so it never even saw the disk (fell back silently to `DataSourceNone`, no error). Confirmed via `wsl --mount <vhdx> --vhd --bare` + loop-mounting the guest's root partition read-only from inside WSL2 to inspect `/var/log/cloud-init.log` directly — a generally useful technique for inspecting a Hyper-V Linux guest's disk from the host without booting it.
3. **Secondary bug**: even after switching to `FileSystemsToCreate = 1` (pure ISO9660), Linux truncated `user-data`/`meta-data` to 8.3 names (`userda~1`/`metada~1`) since plain ISO9660 forbids lowercase/hyphens — cloud-init couldn't find the exact filenames. Fixed by adding Joliet (`FileSystemsToCreate = 3`), which preserves proper long/lowercase names and is what Linux's iso9660 driver actually reads.
4. Also had to `icacls`-grant `NT VIRTUAL MACHINE\Virtual Machines:(R)` on the rebuilt ISO each time it's regenerated — recreating the file drops the ACL Hyper-V needs to attach it, causing "Access is denied" on VM start.

**Verified working (2026-08-12):**
- VM auto-boots to hostname `pihole-vm`, IP `172.28.160.233` (DHCP via Default Switch — not static, may change on reboot; will need a way to keep host DNS pointed at the right IP, e.g. a SYSTEM-level scheduled task that re-queries via `Get-VMNetworkAdapter` and re-applies `Set-DnsClientServerAddress`)
- SSH key login works (`ssh famla@172.28.160.233`, key-only, `ssh_pwauth: false`)
- Passwordless sudo works
- Console password also set for user `famla` (hash baked into cloud-init `user-data`) for emergency/VMConnect access if SSH ever breaks — password: `[REDACTED — live credential, removed before publication to this public repo]` (change this if the VM is ever exposed beyond local-machine-only use)
- `ssh`, `hv-kvp-daemon` services active; `hyperv-daemons`/`openssh-server` packages installed via cloud-init

### Status: ✅ Base VM done. Next: install Pi-hole natively inside it (not via Docker), verify unattended `pihole.toml` config live rather than guessing the schema ahead of time.

### Parallel track: Docker Desktop install still blocked

Retried after enabling WSL feature — still fails with exit code -5, inner installer process exits in <1 second (too fast to be a real attempt). WSL itself now reports fully functional (`wsl --status`/`wsl --version` populated, WSL2 kernel 6.1.18, and a Debian WSL distro was installed and works fine for the mount/debug work above). Downloaded the installer manually to `DockerDesktopInstaller_manual.exe` for direct debugging — not yet resolved. Root cause still unknown; worth checking manually with a visible (non-`--quiet`) install attempt next.

---

## Update — Pi-hole Fully Deployed and Verified ✅

### Pi-hole install (native, unattended, inside `pihole-vm`)

Ran the official installer over SSH: `curl -sSL https://install.pi-hole.net -o /tmp/pi-install.sh`, then `sudo bash /tmp/pi-install.sh --unattended`.

**Key discovery from reading the actual v6.4.3 installer source directly** (more reliable than secondhand guesses): `--unattended` alone does **not** skip the interactive whiptail dialogs (`welcomeDialogs`, `chooseInterface`, `setDNS`, etc.) — those only get skipped when `fresh_install=false`, which the script sets **only if `/etc/pihole/pihole.toml` or `/etc/pihole/setupVars.conf` already exists** before the installer runs. So the working trick is: `sudo mkdir -p /etc/pihole && sudo touch /etc/pihole/pihole.toml` (an empty file is valid) *before* invoking the installer — this makes it take the "update" code path, which is fully non-interactive and skips all dialogs.

**Tradeoff of that trick**: the "update" path also skips the installer's own DNS-upstream-configuration step (that block only runs under `fresh_install=true`), so `dns.upstreams` came out empty (`[]`) — Pi-hole would not have resolved anything until fixed manually. Fixed post-install with the real v6 config CLI: `sudo pihole-FTL --config dns.upstreams '[ "1.1.1.1", "1.0.0.1" ]'` then `sudo systemctl restart pihole-FTL`.

**Also**: `pihole setpassword` with **no arguments removes/disables the password** rather than prompting — not obvious, worth remembering. Correct usage: `pihole setpassword '<password>'`. Admin panel password: `[REDACTED — live credential, removed before publication to this public repo]`.

Install itself succeeded cleanly: Pi-hole core v6.4.3, Web v6.6, FTL v6.7, gravity built with 97,647 blocked domains from Steven Black's hosts list (Pi-hole's default).

### Networking: static IP inside the guest

VM's DHCP-assigned IP (`172.28.160.233` on the `172.28.160.0/20` Default Switch subnet) was pinned to static via a systemd-networkd drop-in (Debian's cloud image uses systemd-networkd, not ifupdown/netplan):

```
# /etc/systemd/network/01-static-eth0.network
[Match]
Name=eth0

[Network]
Address=172.28.160.233/20
Gateway=172.28.160.1
DNS=1.1.1.1
DNS=1.0.0.1
```

Verified this survives a full VM reboot (`Restart-VM`), not just a `systemctl restart systemd-networkd` — same IP, `pihole-FTL` active, DNS resolving, all with zero manual steps. This was necessary because the original DHCP lease could have changed on reboot and broken the host's DNS pointer.

### Windows host wired to Pi-hole

`Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("172.28.160.233", "1.1.1.1")` (Wi-Fi is the only real internet-facing adapter on this machine — Ethernet/other adapters were down/unused). Cloudflare kept as fallback in case the VM is ever down.

**Verified end-to-end from the Windows host itself** (not just from inside the VM):
- `Resolve-DnsName reddit.com` → resolves normally via default DNS (now Pi-hole)
- `Resolve-DnsName doubleclick.net -Server 172.28.160.233` → `0.0.0.0` (blocked, confirms ad-filtering is live for the host)
- `http://172.28.160.233/admin/login` → HTTP 200, admin panel reachable

### Status: ✅ DONE — Pi-hole is live, filtering the host's real DNS traffic, and will come back up automatically on any reboot regardless of which Windows user (including non-admin) logs in, since it lives at the Hyper-V VM level (`vmms`, a SYSTEM service) rather than depending on Docker Desktop or any user session.

**Not yet done**: whole-network reachability (deliberately out of scope per earlier decision — local-machine-only was requested). Docker Desktop install is still separately broken (see above) — unrelated to Pi-hole, which does not depend on Docker at all.

---

## Update — Expanded Blocklists (Porn, Malware, Phishing) + HTTPS + Disk Resize

### Blocklists added (via Pi-hole v6 REST API, not the CLI — see gotcha below)

- **OISD Big** (`https://big.oisd.nl`) — comprehensive ads/trackers/malware/phishing, 251,477 domains
- **OISD NSFW** (`https://nsfw.oisd.nl`) — dedicated porn/adult content blocklist, 488,138 domains
- **Phishing Army** (`https://phishing.army/download/phishing_army_blocklist_extended.txt`) — 155,996 domains
- **Blocklist Project malware list** (`https://raw.githubusercontent.com/blocklistproject/Lists/master/malware.txt`) — 2,656,393 domains (legitimately this large, verified against the list's own header — not a parsing bug)
- Original StevenBlack list (97,647) kept

**Total: 3,489,666 unique domains blocked** across ads, tracking, malware, phishing, and porn/adult content.

**API gotcha**: `pihole api lists` (the CLI wrapper) prompts for a password interactively even when run with plain SSH (breaks non-interactively) unless run with `sudo`. For POSTing new lists, the CLI wrapper doesn't cleanly support it — used `curl` directly against `http://127.0.0.1/api/lists` instead. **The `type` field (block/allow) must be a query parameter (`?type=block`), not a JSON body field** — passing it in the body produces a misleading "Specify type parameter" error even though the body looks correct. Auth: `POST /api/auth` with `{"password": "..."}` returns a `sid` token, passed via `sid:` header on subsequent requests (valid ~30 min).

**Dead URL found**: `https://urlhaus.abuse.ch/downloads/hosts/` (a commonly recommended malware list in older guides) now 404s — abuse.ch changed their format. Swapped for Blocklist Project's malware list instead.

### Disk was too small — resized 3GB → 20GB

Building a database of ~3.5M domains overflowed the original tiny disk (2.8GB, only 900MB free) mid-build, corrupting a `gravity.db_temp` build attempt (though the previously-working smaller database was untouched — Pi-hole doesn't swap in a broken build). Fixed via:
1. `Stop-VM -Force -TurnOff`, then `Resize-VHD -SizeBytes 20GB` on the host (had to fully stop the VM first — resizing while merely "off but not TurnOff'd cleanly" or with a stray WSL mount still attached fails with "process cannot access the file")
2. Started the VM — **cloud-init's built-in `growpart`/`resizefs` boot modules automatically extended the partition and filesystem with zero manual intervention** (this Debian cloud image has `cloud-guest-utils` preinstalled). Manual `growpart`/`resize2fs` were unnecessary (both reported "nothing to do" since cloud-init beat us to it).
3. Re-ran `pihole -g`, which succeeded cleanly with room to spare (3.5M domains, ~200MB RAM used out of the VM's 643MB current allocation — healthy headroom on the 512MB–1GB dynamic memory range).

One transient gravity failure ("database is locked") occurred immediately after the resize-triggered reboot, likely a race between FTL's own restart and gravity.sh's temp-db swap — resolved by simply retrying `pihole -g` once FTL settled.

### HTTPS enabled with a properly trusted certificate (no browser warnings)

Pi-hole v6 already serves HTTPS on port 443 by default with a **self-signed** cert auto-generated at `/etc/pihole/tls.pem` — but self-signed means every browser (Brave, in this case) flags it as insecure. Fixed properly using `mkcert` rather than just accepting the browser warning:

1. `winget install FiloSottile.mkcert` on the Windows host
2. `mkcert -install` — creates a local CA and installs it into the **Windows trust store**, which Brave/Chrome read from on Windows (so no separate per-browser trust step needed)
3. `mkcert -cert-file pihole-cert.pem -key-file pihole-key.pem pi.hole 172.28.160.233 localhost 127.0.0.1` — one cert valid for all the names/IPs used to reach the admin panel, expires 2028-11-11
4. Concatenated cert+key into a single PEM (`Get-Content cert | Set-Content tls.pem; Get-Content key | Add-Content tls.pem` — Pi-hole requires both CERTIFICATE and PRIVATE KEY blocks in one file), copied to the VM as `/etc/pihole/tls.pem` (old self-signed one backed up alongside as `tls.pem.selfsigned.bak`), `chown pihole:pihole`, `chmod 600`
5. `pihole-FTL --config webserver.tls.validity 0` — tells Pi-hole not to auto-regenerate/overwrite this cert (default behavior regenerates self-signed certs every 47 days, which would clobber our real one)
6. Also set `pihole-FTL --config webserver.port '80r,443s,[::]:80r,[::]:443s'` (was `80o,443os,...`) so HTTP now hard-redirects to HTTPS instead of both being independently optional, per the "https instead of http" ask

**Gotcha found**: `pi.hole` didn't resolve from the Windows host via the *default* DNS resolver (worked fine via explicit `-Server 172.28.160.233`, and via the VM's own loopback). Root cause: Windows' "Smart Multi-Homed Name Resolution" races all configured DNS servers (our VM *and* the 1.1.1.1 fallback) and accepts whichever answers first — since `pi.hole` isn't a real TLD, the public 1.1.1.1 resolver returns a fast NXDOMAIN that wins the race before the VM's correct answer arrives. Fixed with a static entry in `C:\Windows\System32\drivers\etc\hosts` (`172.28.160.233 pi.hole`), which bypasses DNS entirely for that one name.

### Status: ✅ Both `https://pi.hole/admin` and `https://172.28.160.233/admin` now load with a fully trusted certificate — no click-through security warnings in Brave (or any Windows-trust-store-respecting browser).

---

## Update — Docker Desktop: Finally Resolved ✅

The direct-installer approach (`INSTALL_DOCKER.ps1`, and later a manually-downloaded installer run with `--verbose`) never worked — every attempt died in under 1 second with exit code `4294967291` (`-5` signed), zero log output (not even the installer's own log-init line), no crash dump, no AV block, no AppLocker denial, all prerequisites confirmed present. Ruled out sandboxing of this automation environment too (retried with sandbox explicitly disabled — same failure). Working theory that was never fully confirmed: Docker's custom bootstrapper needs genuine interactive-desktop/window-station access for some early step (likely related to driver install prompts), which this automation context doesn't have even though it reports session ID 1.

**Fix: `winget install -e --id Docker.DockerDesktop` instead of running the installer directly.** This worked cleanly — winget apparently drives the installer through a different path that doesn't hit whatever the direct-invocation problem was (its own log shows a normal ~28-second run with a real ARP/registry entry created afterward, versus the instant silent death every other method hit).

**Two follow-up steps were still needed after the winget install "succeeded":**
1. The actual GUI app (`Docker Desktop.exe`) needed to be launched once — just starting the `com.docker.service` Windows service was not sufficient on its own to bring up the Docker Engine (the named pipe `docker_engine` wasn't available until the full app launched and orchestrated its WSL2 backend). Launching it directly worked fine (unlike the installer, apparently the already-installed app doesn't hit the same barrier).
2. New/existing terminal sessions needed `resources\bin` on `PATH` to find `docker-credential-desktop.exe` (used for registry auth) — confirmed this is set correctly in the **system** PATH going forward, so this was only an issue for the already-open session used during setup.

**Verified fully working**: `docker version` (client 29.7.2, server/engine 29.7.2, Docker Desktop 4.86.0), `docker ps`, and `docker run hello-world` all succeed end-to-end (image pulled from Docker Hub, container ran, output streamed back).

### Status: ✅ DONE — Docker Desktop installed and fully functional, for general use separate from the Pi-hole VM (which intentionally does not depend on Docker at all, per the earlier design decision).

---

## Session Summary — Everything Resolved

1. **Hyper-V**: repaired (was disabled at the Windows-feature level, not a BIOS/firmware issue as first suspected) ✅
2. **Pi-hole**: running natively in a dedicated auto-starting Hyper-V VM, independent of Docker/user login, HTTPS with a trusted cert, 3.49M domains blocked across ads/malware/phishing/porn ✅
3. **Docker Desktop**: installed and verified working (via `winget`, not the direct installer) for general/other use ✅

All three original goals from this session are complete.

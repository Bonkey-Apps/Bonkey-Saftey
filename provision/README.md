# provision

Rebuilds the Pi-hole server this repo's lists run on. One script:

```powershell
# elevated PowerShell
.\New-PiholeVM.ps1
```

It creates the internal switch, converts the Debian 12 cloud image, seeds
cloud-init, builds the VM, installs Pi-hole, subscribes every list, rebuilds
gravity, and verifies the result. Roughly fifteen minutes, most of it gravity
downloading ~3.9M domains.

## What it builds

| | |
|---|---|
| Guest | Debian 12 bookworm, Gen2 UEFI, Secure Boot **off** |
| Sizing | 1 vCPU, 1 GB startup / 512 MB minimum dynamic, 20 GB disk |
| Network | internal switch `Pihole Internal`; host `10.77.77.1` + `fd77:77:77::1`, VM `10.77.77.10` + `fd77:77:77::10` |
| Pi-hole | v6, upstreams `1.1.1.1` / `1.0.0.1`, `listeningMode = LOCAL`, blocking mode `NULL` |
| Lists | 11 block + 2 allow, matching the live box |

Secure Boot is off because Debian's generic cloud image is not signed for the
default Hyper-V UEFI CA. It will not boot otherwise.

## Parameters worth knowing

| Flag | Default | Why you'd change it |
|---|---|---|
| `-GuestUser` | your Windows username | The Linux account created in the guest. Normalised to lowercase and stripped of characters `useradd` rejects. |
| `-SshPublicKeyPath` | `~\.ssh\id_ed25519.pub` | Key authorised for that account. Password SSH stays disabled, so a valid key is required. |
| `-PiholePassword` | prompted | Web admin password. Never stored in this repo. |
| `-SkipHostDns` | off | Leave this machine's DNS alone instead of pointing it at the VM. |
| `-Force` | off | Rebuild an existing VM. **Destroys its disk.** |
| `-MemoryStartupBytes` | `1GB` | The live VM runs smaller, but `pihole -g` is memory-hungry at ~3.9M domains. |

## Prerequisites

- Hyper-V already installed and enabled — the script checks but will not install it
- `qemu-img` for the qcow2 → vhdx conversion: `winget install --id SoftwareFreedomConservancy.QEMU`
- An SSH keypair

`oscdimg` from the Windows ADK is used for the cloud-init seed if present. It
usually is not, so the script falls back to a small FAT32 VHDX labelled
`CIDATA`, which NoCloud accepts identically. No ADK install needed.

## The IPv6 address is not decoration

The VM gets a ULA (`fd77:77:77::10`) and the host end of the switch joins the
same `/64`. This is load-bearing.

Windows prefers IPv6 resolvers over IPv4. If Pi-hole is IPv4-only, a
router-advertised IPv6 DNS server wins every lookup and **all filtering is
silently bypassed** — blocking still tests perfectly if you query Pi-hole
directly with `-Server`, because that is not the path applications use. That
failure mode cost real debugging time here.

The script's last step points this machine's physical adapters at
`fd77:77:77::10` first, then `10.77.77.10`, which overrides the
router-advertised entry.

## Other devices are still bypassing

Fixing this machine does not fix the network. Until the router hands out
`10.77.77.10` as its DNS server **and** stops advertising itself as an IPv6
resolver, every other device — phones, tablets, the kids' devices — resolves ad
domains normally. That change is in the router admin and cannot be scripted
from here.

## Verifying

The script ends with a table that must read:

```
PASS  cdn.taboola.com                           0.0.0.0
PASS  domainreferrer3.microsoftcasualgames.com  0.0.0.0
PASS  tpsc-uw1.doubleverify.com                 0.0.0.0
PASS  settings-win.data.microsoft.com           <real IP>
PASS  assets.msn.com                            <real IP>
```

The last two are the important ones. If they come back `0.0.0.0`, the allowlist
did not apply — Game Pass installs will fail with `0x00000001` and some Casual
Games will hang on the loading screen. See the allowlist notes in the root
ReadMe.

To re-check by hand later, without `-Server` so you test the real path:

```powershell
Resolve-DnsName cdn.taboola.com | Select-Object Name, IPAddress
```

## Undoing it

`Remove-PiholeVM.ps1` reverses every change `New-PiholeVM.ps1` made to this
Windows machine.

```powershell
# elevated PowerShell -- put DNS back and stop, VM left running
.\Remove-PiholeVM.ps1 -DnsOnly

# or the full teardown: DNS, VM, disks, switch
.\Remove-PiholeVM.ps1

# see what it would remove first
.\Remove-PiholeVM.ps1 -WhatIf
```

Reach for `-DnsOnly` first when something on this machine has stopped working.
It is the fast, reversible half: DNS goes back to DHCP, the resolver cache is
flushed, and the VM keeps running so you can re-point at it once the cause is
understood.

### What it touches, and what it deliberately does not

| Undone | Left alone |
|---|---|
| DNS servers on every physical adapter (back to DHCP unless `-DnsServers` is given) | Hyper-V — a prerequisite, not something the script installed |
| The `pihole-vm` VM, its vhdx, and the cloud-init seed | `qemu-img` — likewise |
| `C:\pihole-vm` (`-KeepImage` keeps the ~350 MB cloud image) | Your SSH keypair |
| The `Pihole Internal` switch and host `10.77.77.1` / `fd77:77:77::1` | The router — if its DNS was pointed at `10.77.77.10` by hand, change that back in the router admin |
| The staged adlist SQL in `%TEMP%` and the `known_hosts` entry for the VM | Pi-hole config and gravity — those live inside the VM and go with it |

The switch is kept, with a warning, if another VM is still attached to it.

`-DnsServers` exists for machines that had **static** DNS before provisioning
overwrote it. The original value is not recorded anywhere, so the default is a
reset to DHCP; pass the old addresses explicitly if DHCP is not what you want.

### Why "everything broke" is usually the DNS step

The last step of `New-PiholeVM.ps1` points this machine's adapters at the VM.
From that moment every lookup on the machine goes through Pi-hole, so a domain
that is blocked — or the VM simply not running — fails for the whole system,
not just for games. Two failure shapes worth recognising:

- **Nothing resolves at all.** The VM is down, paused, or the switch was
  removed. `-DnsOnly` restores service immediately.
- **One application breaks, everything else is fine.** Something that
  application needs is on a block list. Find it before undoing anything:

  ```bash
  ssh <user>@10.77.77.10 'sudo pihole -t'
  ```

  Reproduce the failure and watch for a blocked domain belonging to the tool.
  The fix is one line in `lists/allowlist.txt`, not a teardown.

A live example of the second shape: `big.oisd.nl` blocks `api.statsig.com`,
`api.statsigcdn.com` and `statsigapi.net`. Statsig is a feature-flag service
that several developer tools — Claude Code among them — call at startup, so
they stall or fall back to defaults while the rest of the machine looks
perfectly healthy. The first-party `anthropic.com` and `claude.ai` domains are
**not** blocked by any list in this pack; only the flag endpoints are. If those
tools matter on this network, allow the three hosts rather than dropping the
list:

```
api.statsig.com
api.statsigcdn.com
statsigapi.net
```

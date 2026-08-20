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

The script's last step points this machine at `fd77:77:77::10` first, then
`10.77.77.10`, which overrides the router-advertised entry.

It picks the adapter **carrying the default route**, not `-Physical`. On a
Hyper-V host with an external switch those are different adapters: the physical
NIC is only the underlay, and the host's IP stack lives on the `vEthernet`. An
earlier version used `-Physical`, set resolvers on the wrong adapter, and left
this machine with no working DNS. Before changing anything the step now proves
Pi-hole answers on both addresses and skips with a warning if it does not.

If host DNS ever does break, reset the adapter to DHCP from an elevated
PowerShell:

```powershell
Set-DnsClientServerAddress -InterfaceAlias 'vEthernet (LAN Bridge)' -ResetServerAddresses
Clear-DnsClientCache
```

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

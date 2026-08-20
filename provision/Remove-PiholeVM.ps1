<#
.SYNOPSIS
    Reverses everything New-PiholeVM.ps1 changed on this Windows machine.

.DESCRIPTION
    New-PiholeVM.ps1 touches exactly four things outside the guest VM:

      1. This machine's DNS servers -- every physical adapter that was Up got
         repointed at the Pi-hole VM (fd77:77:77::10, then 10.77.77.10).
      2. A Hyper-V internal switch 'Pihole Internal', plus the host-side
         addresses 10.77.77.1 and fd77:77:77::1 on its vEthernet adapter.
      3. The VM 'pihole-vm' and the files under C:\pihole-vm (cloud image,
         converted vhdx, cloud-init seed).
      4. A short-lived SQL file in %TEMP%.

    Everything else -- Pi-hole itself, gravity, the subscribed lists -- lives
    inside the VM and disappears with it. Nothing was written to the registry,
    no firewall rules were added, and Hyper-V and qemu-img were prerequisites
    rather than installs, so this script leaves all three alone.

    Item 1 is the one that breaks things. Once DNS points at the VM, anything
    the VM cannot resolve -- because it is blocked, or because the VM is not
    running -- fails for the whole machine. Run with -DnsOnly to undo just that
    and keep the VM for later.

.PARAMETER DnsOnly
    Restore DNS and stop. Leaves the VM, the switch and C:\pihole-vm in place.

.PARAMETER DnsServers
    What to set DNS back to. Omit to revert to DHCP (the usual answer -- the
    router hands out its own resolver again). Pass explicit addresses only if
    this machine had static DNS before New-PiholeVM.ps1 overwrote it, since
    that original value is not recorded anywhere.

.PARAMETER KeepImage
    Keep C:\pihole-vm\debian-12-generic-amd64.qcow2 so a later rebuild does not
    re-download ~350 MB. Everything else under the work directory still goes.

.PARAMETER KeepSwitch
    Leave the 'Pihole Internal' switch and its host addresses alone. Use this if
    something else was attached to that switch.

.EXAMPLE
    .\Remove-PiholeVM.ps1 -DnsOnly

    The fast fix when name resolution broke. Puts DNS back on DHCP and flushes
    the cache; the VM keeps running and can be re-pointed at later.

.EXAMPLE
    .\Remove-PiholeVM.ps1

    Full teardown: DNS, VM, disks, switch.

.EXAMPLE
    .\Remove-PiholeVM.ps1 -WhatIf

    Show what would be removed without touching anything.
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]   $VMName      = 'pihole-vm',
    [string]   $SwitchName  = 'Pihole Internal',
    [string]   $WorkDir     = 'C:\pihole-vm',
    [string]   $VMIPv4      = '10.77.77.10',
    [string[]] $DnsServers,
    [switch]   $DnsOnly,
    [switch]   $KeepImage,
    [switch]   $KeepSwitch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m"   -ForegroundColor DarkGray }
function Ok  ($m) { Write-Host "    $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "    $m"   -ForegroundColor Yellow }

# ------------------------------------------------------------------ host DNS --
# First, because it is the step that unbreaks the machine. Everything below is
# cleanup and can fail without leaving name resolution broken.
Step 'Restoring this machine''s DNS'

$touched = 0
foreach ($nic in Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }) {
    $current = (Get-DnsClientServerAddress -InterfaceIndex $nic.ifIndex |
                  ForEach-Object { $_.ServerAddresses }) -join ', '
    Info "$($nic.Name) currently: $(if ($current) { $current } else { '(none)' })"

    if ($DnsServers) {
        if ($PSCmdlet.ShouldProcess($nic.Name, "Set DNS to $($DnsServers -join ', ')")) {
            Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $DnsServers
            Ok "$($nic.Name) -> $($DnsServers -join ', ')"
            $touched++
        }
    } else {
        if ($PSCmdlet.ShouldProcess($nic.Name, 'Reset DNS to DHCP')) {
            Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses
            Ok "$($nic.Name) -> DHCP"
            $touched++
        }
    }
}

if ($touched) {
    if ($PSCmdlet.ShouldProcess('DNS client cache', 'Clear')) {
        Clear-DnsClientCache
        Ok 'resolver cache flushed'
    }
} else {
    Warn 'No physical adapter was Up -- nothing to restore. Check Wi-Fi/Ethernet is connected.'
}

if ($DnsOnly) {
    Write-Host @"

  DNS restored. The VM '$VMName' is still running and still filtering anything
  pointed at it deliberately.

  Confirm resolution works again:
    Resolve-DnsName api.anthropic.com | Select-Object Name, IPAddress

"@ -ForegroundColor Cyan
    return
}

# ------------------------------------------------------------------------ VM --
Step "VM '$VMName'"

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Warn 'Hyper-V cmdlets unavailable -- skipping VM, disk and switch cleanup.'
    return
}

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($vm) {
    # Capture the disk paths before Remove-VM forgets them. Remove-VM detaches
    # VHDs rather than deleting them, so they have to be handled by name.
    $attached = @(Get-VMHardDiskDrive -VMName $VMName | ForEach-Object { $_.Path })
    $attached += @(Get-VMDvdDrive -VMName $VMName | Where-Object { $_.Path } | ForEach-Object { $_.Path })

    if ($PSCmdlet.ShouldProcess($VMName, 'Stop and remove VM')) {
        if ($vm.State -ne 'Off') {
            Stop-VM $VMName -TurnOff -Force
            Ok 'powered off'
        }
        Remove-VM $VMName -Force
        Ok 'VM removed'
    }

    foreach ($d in $attached | Where-Object { $_ -and (Test-Path $_) }) {
        if ($PSCmdlet.ShouldProcess($d, 'Delete virtual disk')) {
            # A crashed run can leave the seed vhdx mounted on a drive letter.
            Dismount-VHD -Path $d -ErrorAction SilentlyContinue
            Remove-Item $d -Force
            Ok "deleted $d"
        }
    }
} else {
    Info 'not present'
}

# -------------------------------------------------------------- work directory --
Step "Work directory $WorkDir"

if (Test-Path $WorkDir) {
    $qcow = Join-Path $WorkDir 'debian-12-generic-amd64.qcow2'
    $keep = $KeepImage -and (Test-Path $qcow)

    foreach ($item in Get-ChildItem $WorkDir -Force) {
        if ($keep -and $item.FullName -eq $qcow) {
            Info "keeping $($item.Name) (-KeepImage)"
            continue
        }
        if ($PSCmdlet.ShouldProcess($item.FullName, 'Delete')) {
            Remove-Item $item.FullName -Recurse -Force
            Ok "deleted $($item.Name)"
        }
    }

    if (-not $keep -and -not (Get-ChildItem $WorkDir -Force)) {
        if ($PSCmdlet.ShouldProcess($WorkDir, 'Remove directory')) {
            Remove-Item $WorkDir -Force
            Ok 'directory removed'
        }
    }
} else {
    Info 'not present'
}

# -------------------------------------------------------------------- switch --
Step "Internal switch '$SwitchName'"

if ($KeepSwitch) {
    Info 'kept (-KeepSwitch)'
} elseif (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
    # Anything else on this switch loses its network, so say so rather than
    # silently taking it down.
    # VM adapters only. Get-VMNetworkAdapter -All would also return the switch's
    # own management-OS adapter, which is always there and is not another tenant.
    $others = @(Get-VM | Get-VMNetworkAdapter |
                  Where-Object { $_.SwitchName -eq $SwitchName -and $_.VMName -ne $VMName })
    if ($others) {
        Warn "still in use by: $(($others | ForEach-Object { $_.VMName } | Sort-Object -Unique) -join ', ')"
        Warn 'left in place. Re-run with those VMs detached, or remove it by hand.'
    } elseif ($PSCmdlet.ShouldProcess($SwitchName, 'Remove switch (also removes host 10.77.77.1 / fd77:77:77::1)')) {
        Remove-VMSwitch -Name $SwitchName -Force
        Ok 'removed, along with its host-side addresses'
    }
} else {
    Info 'not present'
}

# ------------------------------------------------------------------- leftovers --
Step 'Leftovers'

$sqlLocal = Join-Path $env:TEMP 'bonkey-adlists.sql'
if (Test-Path $sqlLocal) {
    if ($PSCmdlet.ShouldProcess($sqlLocal, 'Delete')) {
        Remove-Item $sqlLocal -Force
        Ok 'removed staged adlist SQL'
    }
} else {
    Info 'no staged adlist SQL'
}

# Added by ssh -o StrictHostKeyChecking=accept-new during provisioning.
$knownHosts = Join-Path $env:USERPROFILE '.ssh\known_hosts'
if ((Test-Path $knownHosts) -and (Select-String -Path $knownHosts -Pattern $VMIPv4 -SimpleMatch -Quiet)) {
    if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess("known_hosts entry for $VMIPv4", 'Remove')) {
            & ssh-keygen -R $VMIPv4 2>&1 | Out-Null
            Ok "removed known_hosts entry for $VMIPv4"
        }
    } else {
        Warn "known_hosts still trusts $VMIPv4; ssh-keygen not found to remove it."
    }
} else {
    Info 'no known_hosts entry'
}

Write-Host @"

  Undone. DNS is back on $(if ($DnsServers) { $DnsServers -join ', ' } else { 'DHCP' }), the VM and its
  disks are gone, and the switch is $(if ($KeepSwitch) { 'kept' } else { 'removed' }).

  Left alone on purpose: Hyper-V and qemu-img (prerequisites, not installs),
  your SSH keypair, and the router -- if its DNS was ever pointed at
  $VMIPv4 by hand, that still needs changing back in the router admin.

  Confirm resolution works:
    Resolve-DnsName api.anthropic.com | Select-Object Name, IPAddress

"@ -ForegroundColor Cyan

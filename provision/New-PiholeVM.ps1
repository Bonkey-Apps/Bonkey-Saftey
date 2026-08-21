<#
.SYNOPSIS
    Builds the Bonkey-Saftey Pi-hole VM on Hyper-V from scratch.

.DESCRIPTION
    Reproduces the running pihole-vm: a Debian 12 Gen2 VM on an internal switch,
    with Pi-hole v6 configured and every Bonkey-Saftey list subscribed.

    Assumes Hyper-V is already installed and enabled. Must run elevated.

    Safe to re-run: it skips anything that already exists unless -Force is
    given, and it never writes a password into the repo.

.PARAMETER PiholePassword
    Web admin password. Prompted for if omitted. The live VM's password hash is
    deliberately NOT baked in -- this repo is public.

.PARAMETER SshPublicKeyPath
    Public key authorized for the guest account. Password SSH stays disabled.

.PARAMETER Force
    Delete and rebuild an existing VM of the same name. Destroys its disk.

.EXAMPLE
    .\New-PiholeVM.ps1

.EXAMPLE
    .\New-PiholeVM.ps1 -SkipHostDns
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]        $VMName             = 'pihole-vm',
    [string]        $SwitchName         = 'Pihole Internal',
    [string]        $WorkDir            = 'C:\pihole-vm',

    # Network. Host takes .1, the VM takes .10, on an isolated internal switch.
    [string]        $HostIPv4           = '10.77.77.1',
    [string]        $VMIPv4             = '10.77.77.10',
    [int]           $PrefixV4           = 24,
    [string]        $HostIPv6           = 'fd77:77:77::1',
    [string]        $VMIPv6             = 'fd77:77:77::10',
    [int]           $PrefixV6           = 64,

    # Guest sizing. The live VM reports 1 vCPU / ~387 MB usable / 20 GB disk.
    [int64]         $MemoryStartupBytes = 1GB,
    [int64]         $MemoryMinimumBytes = 512MB,
    [int]           $CpuCount           = 1,
    [int64]         $DiskSize           = 20GB,

    # Login created inside the guest. Defaults to whoever is running the script.
    [string]        $GuestUser          = $env:USERNAME,
    [string]        $SshPublicKeyPath   = "$env:USERPROFILE\.ssh\id_ed25519.pub",
    [securestring]  $PiholePassword,
    [string[]]      $UpstreamDns        = @('1.1.1.1', '1.0.0.1'),
    [switch]        $SkipHostDns,
    [switch]        $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Windows usernames allow characters Linux does not. Normalise before the name
# reaches cloud-init, or useradd fails and the VM boots with no way in.
$GuestUser = ($GuestUser.ToLower() -replace '[^a-z0-9_-]', '')
if (-not $GuestUser -or $GuestUser -notmatch '^[a-z_]') {
    throw "Cannot derive a valid Linux username from '$env:USERNAME'. Pass -GuestUser explicitly."
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m"   -ForegroundColor DarkGray }
function Ok  ($m) { Write-Host "    $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "    $m"   -ForegroundColor Yellow }

# The exact list set running on the live box. type 0 = block, 1 = allow.
$ADLISTS = @(
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-social/hosts' }
    @{ Type = 0; Url = 'https://big.oisd.nl' }
    @{ Type = 0; Url = 'https://nsfw.oisd.nl' }
    @{ Type = 0; Url = 'https://phishing.army/download/phishing_army_blocklist_extended.txt' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/blocklistproject/Lists/master/malware.txt' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/Jayconius/Pi-Hole-Gaming-Lists/main/Gaming-Ads-Blocklist.txt' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/DandelionSprout/adfilt/master/GameConsoleAdblockList.txt' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/ms-game-ads.txt' }
    @{ Type = 0; Url = 'https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/ad-networks.txt' }
    @{ Type = 1; Url = 'https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/allowlist.txt' }
    @{ Type = 1; Url = 'https://raw.githubusercontent.com/Jayconius/Pi-Hole-Gaming-Lists/main/Gaming-Whitelist.txt' }
)

$DEBIAN_IMAGE_URL = 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2'

# ---------------------------------------------------------------- preflight --
Step 'Preflight'

if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State -ne 'Enabled') {
    throw 'Hyper-V is not enabled. This script assumes it is already installed.'
}
Ok 'Hyper-V enabled'

if (-not (Test-Path $SshPublicKeyPath)) {
    throw "No SSH public key at $SshPublicKeyPath. Generate one with: ssh-keygen -t ed25519"
}
$sshKey = (Get-Content $SshPublicKeyPath -Raw).Trim()
Ok "SSH key: $($sshKey.Split(' ')[-1])"

$qemuImg = (Get-Command qemu-img -ErrorAction SilentlyContinue).Source
if (-not $qemuImg) {
    throw 'qemu-img not found. Install it: winget install --id SoftwareFreedomConservancy.QEMU'
}
Ok "qemu-img: $qemuImg"

if (-not $PiholePassword) {
    $PiholePassword = Read-Host -AsSecureString 'Pi-hole web admin password'
}
$plainPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
             [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PiholePassword))
if (-not $plainPw) { throw 'A password is required.' }

$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
    throw "VM '$VMName' already exists. Re-run with -Force to rebuild it (destroys its disk)."
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ------------------------------------------------------------------- switch --
Step "Internal switch '$SwitchName'"

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Ok 'created'
} else {
    Info 'already exists'
}

# The host end of the switch. The IPv6 address matters: Windows prefers IPv6
# resolvers, so Pi-hole needs one or a router-advertised DNS silently wins.
$hostIf = Get-NetAdapter -Name "vEthernet ($SwitchName)"
foreach ($a in @(
    @{ IP = $HostIPv4; Prefix = $PrefixV4; Family = 'IPv4' },
    @{ IP = $HostIPv6; Prefix = $PrefixV6; Family = 'IPv6' })) {
    $have = Get-NetIPAddress -InterfaceIndex $hostIf.ifIndex -AddressFamily $a.Family -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq $a.IP }
    if (-not $have) {
        New-NetIPAddress -InterfaceIndex $hostIf.ifIndex -IPAddress $a.IP -PrefixLength $a.Prefix | Out-Null
        Ok "host $($a.Family) $($a.IP)/$($a.Prefix)"
    } else {
        Info "host $($a.Family) already set"
    }
}

# --------------------------------------------------------------------- disk --
Step 'Guest disk'

$qcow = Join-Path $WorkDir 'debian-12-generic-amd64.qcow2'
$vhdx = Join-Path $WorkDir "$VMName.vhdx"

if (-not (Test-Path $qcow)) {
    Info "downloading $DEBIAN_IMAGE_URL"
    Invoke-WebRequest -Uri $DEBIAN_IMAGE_URL -OutFile $qcow
    Ok 'image downloaded'
} else {
    Info 'cloud image already present'
}

if ((Test-Path $vhdx) -and $Force) { Remove-Item $vhdx -Force }
if (-not (Test-Path $vhdx)) {
    Info 'converting qcow2 -> vhdx (a few minutes)'
    & $qemuImg convert -f qcow2 -O vhdx -o subformat=dynamic $qcow $vhdx
    if ($LASTEXITCODE -ne 0) { throw 'qemu-img convert failed.' }
    Resize-VHD -Path $vhdx -SizeBytes $DiskSize
    Ok "vhdx ready at $([math]::Round($DiskSize / 1GB))GB"
} else {
    Info 'vhdx already present'
}

# --------------------------------------------------------------- cloud-init --
Step 'cloud-init seed'

$seedDir = Join-Path $WorkDir 'seed'
Remove-Item $seedDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $seedDir | Out-Null

@"
instance-id: $VMName-001
local-hostname: $VMName
"@ | Set-Content (Join-Path $seedDir 'meta-data') -Encoding ascii

# Static addressing on both families. cloud-init network regeneration is
# disabled so netplan stays authoritative after first boot.
$nameservers = $UpstreamDns -join ', '
@"
#cloud-config
hostname: $VMName
fqdn: $VMName.local
manage_etc_hosts: true

users:
  - name: $GuestUser
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - $sshKey

ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: false
packages:
  - hyperv-daemons
  - openssh-server
  - curl
  - ca-certificates

write_files:
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: "network: {config: disabled}\n"
  - path: /etc/netplan/50-cloud-init.yaml
    permissions: '0600'
    content: |
      network:
          ethernets:
              eth0:
                  addresses:
                      - $VMIPv4/$PrefixV4
                      - $VMIPv6/$PrefixV6
                  routes:
                      - to: default
                        via: $HostIPv4
                  nameservers:
                      addresses: [$nameservers]
                  match:
                      name: e*
                  set-name: eth0
          version: 2

runcmd:
  - [ systemctl, enable, --now, hv-kvp-daemon.service ]
  - [ systemctl, enable, --now, ssh.service ]
  - [ netplan, apply ]

final_message: "cloud-init complete"
"@ | Set-Content (Join-Path $seedDir 'user-data') -Encoding ascii

$seedIso  = Join-Path $WorkDir 'seed.iso'
$seedVhdx = $null
Remove-Item $seedIso -Force -ErrorAction SilentlyContinue

# NoCloud accepts an ISO or any filesystem labelled CIDATA. oscdimg ships with
# the Windows ADK and is often absent, so fall back to a small FAT32 VHDX.
$oscdimg = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools' `
             -Filter oscdimg.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($oscdimg) {
    & $oscdimg.FullName -j2 -lCIDATA $seedDir $seedIso | Out-Null
    Ok 'seed.iso built with oscdimg'
} else {
    Info 'oscdimg not found; building a CIDATA VHDX instead'
    $seedVhdx = Join-Path $WorkDir 'seed.vhdx'
    Remove-Item $seedVhdx -Force -ErrorAction SilentlyContinue
    $disk = New-VHD -Path $seedVhdx -SizeBytes 64MB -Fixed |
            Mount-VHD -Passthru |
            Initialize-Disk -PartitionStyle MBR -PassThru
    $part = $disk | New-Partition -UseMaximumSize -AssignDriveLetter
    $part | Format-Volume -FileSystem FAT32 -NewFileSystemLabel CIDATA -Confirm:$false | Out-Null
    Copy-Item "$seedDir\*" "$($part.DriveLetter):\" -Force
    Dismount-VHD -Path $seedVhdx
    Ok 'seed.vhdx built'
}

# ----------------------------------------------------------------------- VM --
Step "VM '$VMName'"

if ($existing) {
    Stop-VM $VMName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM $VMName -Force
}

New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes `
       -VHDPath $vhdx -SwitchName $SwitchName | Out-Null
Set-VMProcessor $VMName -Count $CpuCount
Set-VMMemory    $VMName -DynamicMemoryEnabled $true `
                        -MinimumBytes $MemoryMinimumBytes -StartupBytes $MemoryStartupBytes
# Debian's cloud image is not signed for the default Hyper-V UEFI CA.
Set-VMFirmware  $VMName -EnableSecureBoot Off
Set-VM          $VMName -AutomaticStartAction Start -AutomaticStopAction ShutDown -CheckpointType Disabled

if ($seedVhdx) { Add-VMHardDiskDrive $VMName -Path $seedVhdx }
else           { Add-VMDvdDrive      $VMName -Path $seedIso }

Set-VMFirmware $VMName -FirstBootDevice (Get-VMHardDiskDrive $VMName | Where-Object { $_.Path -eq $vhdx })
Ok "$CpuCount vCPU, $([math]::Round($MemoryStartupBytes / 1MB))MB, Secure Boot off"

Start-VM $VMName
Ok 'started'

# ------------------------------------------------------------- wait for SSH --
Step 'Waiting for first boot (cloud-init installs packages; allow a few minutes)'

$deadline = (Get-Date).AddMinutes(10)
$up = $false
do {
    Start-Sleep -Seconds 10
    $up = (Test-NetConnection $VMIPv4 -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded
    Write-Host '.' -NoNewline
} until ($up -or (Get-Date) -gt $deadline)
Write-Host ''
if (-not $up) { throw "VM never came up on ${VMIPv4}:22. Check the console with vmconnect." }
Ok 'SSH reachable'

$sshArgs = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15', "$GuestUser@$VMIPv4")
function Guest([string] $cmd) {
    $out = & ssh @sshArgs $cmd 2>&1
    if ($LASTEXITCODE -ne 0) { throw "guest command failed: $cmd`n$out" }
    $out
}

# ------------------------------------------------------------------ Pi-hole --
Step 'Installing Pi-hole'

Guest 'command -v pihole >/dev/null || curl -sSL https://install.pi-hole.net | sudo bash /dev/stdin --unattended' | Out-Null
Ok (Guest 'pihole -v | head -1')

Step 'Applying configuration'

$upstreamJson = '[' + (($UpstreamDns | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'
$settings = @(
    @{ Key = 'dns.upstreams';          Value = $upstreamJson }
    @{ Key = 'dns.listeningMode';      Value = 'LOCAL' }
    @{ Key = 'dns.CNAMEdeepInspect';   Value = 'true' }   # catches ad hosts via their CNAME target
    @{ Key = 'dns.blockESNI';          Value = 'true' }
    @{ Key = 'dns.blocking.mode';      Value = 'NULL' }
    @{ Key = 'webserver.port';         Value = '80r,443s,[::]:80r,[::]:443s' }
    @{ Key = 'webserver.domain';       Value = 'pi.hole' }
    @{ Key = 'webserver.tls.validity'; Value = '0' }      # 0 = never rotate the self-signed cert
)
foreach ($s in $settings) {
    Guest "sudo pihole-FTL --config $($s.Key) '$($s.Value)'" | Out-Null
    Info "$($s.Key) = $($s.Value)"
}

$escapedPw = $plainPw.Replace("'", "'\''")
Guest "sudo pihole setpassword '$escapedPw'" | Out-Null
Ok 'web password set'

Step 'Subscribing lists'

$sql = New-Object System.Collections.Generic.List[string]
$sql.Add('BEGIN TRANSACTION;')
foreach ($a in $ADLISTS) {
    $u = $a.Url.Replace("'", "''")
    $sql.Add("INSERT OR IGNORE INTO adlist (address, type, enabled, comment) VALUES ('$u', $($a.Type), 1, 'bonkey-saftey');")
    $sql.Add("UPDATE adlist SET type = $($a.Type), enabled = 1 WHERE address = '$u';")
    $sql.Add("INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, 0 FROM adlist WHERE address = '$u';")
}
$sql.Add('COMMIT;')

$sqlLocal = Join-Path $env:TEMP 'bonkey-adlists.sql'
Set-Content $sqlLocal ($sql -join "`n") -Encoding ascii
& scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new $sqlLocal "$GuestUser@${VMIPv4}:/tmp/adlists.sql" | Out-Null
Guest 'sudo pihole-FTL sqlite3 /etc/pihole/gravity.db ".read /tmp/adlists.sql" && rm -f /tmp/adlists.sql' | Out-Null
Remove-Item $sqlLocal -Force
$allowCount = ($ADLISTS | Where-Object { $_.Type -eq 1 }).Count
Ok "$($ADLISTS.Count) lists registered ($allowCount allow)"

Step 'Scheduling hourly gravity updates'

# Its own file. /etc/cron.d/pihole is under Pi-hole's source control and is
# overwritten on every update -- its header says so. The weekly entry there is
# left alone; one redundant run a week costs nothing.
#
# Guards matter on a box this small (the live VM has ~387 MB and no swap):
#   flock -n    an hourly tick must never overlap a slow previous run or the
#               Sunday weekly one. -n skips instead of queueing, and a skipped
#               hour self-heals on the next tick.
#   nice/ionice keep FTL answering DNS while gravity churns ~3.9M domains.
#   minute 17   off the hour, to be polite to raw.githubusercontent.com.
$cronLine = '17 *   * * *   pihole   PATH="$PATH:/usr/sbin:/usr/local/bin/" ' +
            'flock -n /run/lock/pihole-gravity.lock nice -n 10 ionice -c3 ' +
            'pihole updateGravity >/var/log/pihole/gravity-hourly.log 2>&1 ' +
            '|| cat /var/log/pihole/gravity-hourly.log'

$cronFile = '/etc/cron.d/pihole-gravity-hourly'
Guest "printf '%s
' '# bonkey-saftey: rebuild gravity every hour.' '$cronLine' | sudo tee $cronFile >/dev/null" | Out-Null
Guest "sudo chown root:root $cronFile && sudo chmod 644 $cronFile" | Out-Null
Guest 'sudo systemctl reload-or-restart cron' | Out-Null
Ok 'hourly gravity job installed (:17 past the hour)'

Step 'Building gravity (downloads several million domains; slow)'
Guest 'sudo pihole -g' | Select-Object -Last 6 | ForEach-Object { Info $_ }

# ----------------------------------------------------------------- host DNS --
if (-not $SkipHostDns) {
    Step 'Pointing this machine at Pi-hole'

    # Pre-flight. Setting resolvers the host cannot reach leaves it with no DNS
    # at all -- that has happened here. Prove both families answer first, and
    # skip with a warning rather than break name resolution.
    $reachable = $true
    foreach ($srv in @($VMIPv6, $VMIPv4)) {
        $probe = Resolve-DnsName 'example.com' -Server $srv -Type A -DnsOnly `
                    -QuickTimeout -ErrorAction SilentlyContinue
        if (-not $probe) {
            Warn "Pi-hole did not answer on $srv -- leaving host DNS alone"
            $reachable = $false
        }
    }

    if (-not $reachable) {
        Warn 'host DNS unchanged. Boot/repair the VM, then set host DNS by hand.'
        Warn "  Set-DnsClientServerAddress -InterfaceIndex <n> -ServerAddresses @('$VMIPv6','$VMIPv4')"
    } else {
        # The adapter carrying the default route, NOT -Physical. On a Hyper-V
        # host with an external switch the physical NIC is only the underlay:
        # the host's IP stack lives on the vEthernet, so -Physical sets
        # resolvers on an adapter that does not resolve anything.
        $routed = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Sort-Object RouteMetric |
                    ForEach-Object { Get-NetAdapter -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue } |
                    Where-Object { $_.Status -eq 'Up' } |
                    Sort-Object -Property ifIndex -Unique

        if (-not $routed) {
            Warn 'no default-route adapter found -- leaving host DNS alone'
        } else {
            # Both families, IPv6 first. Windows prefers IPv6 resolvers, so
            # leaving a router-advertised IPv6 DNS in place silently bypasses
            # all filtering.
            $routed | ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses @($VMIPv6, $VMIPv4)
                Info "$($_.Name) (ifIndex $($_.ifIndex)) -> $VMIPv6, $VMIPv4"
            }
            Clear-DnsClientCache

            $undo = ($routed | ForEach-Object { $_.ifIndex }) -join ', '
            Info "to undo: Set-DnsClientServerAddress -InterfaceIndex $undo -ResetServerAddresses"
        }
    }
} else {
    Info 'skipped host DNS (-SkipHostDns)'
}

# ------------------------------------------------------------------- verify --
Step 'Verification'

$checks = @(
    @{ Domain = 'cdn.taboola.com';                          Expect = 'blocked' }
    @{ Domain = 'domainreferrer3.microsoftcasualgames.com'; Expect = 'blocked' }
    @{ Domain = 'tpsc-uw1.doubleverify.com';                Expect = 'blocked' }
    @{ Domain = 'settings-win.data.microsoft.com';          Expect = 'allowed' }
    @{ Domain = 'assets.msn.com';                           Expect = 'allowed' }
)
$fail = 0
foreach ($c in $checks) {
    $ips = (Resolve-DnsName $c.Domain -Server $VMIPv4 -Type A -DnsOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) -join ','
    $actual = if ($ips -eq '0.0.0.0' -or -not $ips) { 'blocked' } else { 'allowed' }
    if ($actual -eq $c.Expect) { $mark = 'PASS' } else { $mark = 'FAIL'; $fail++ }
    '{0}  {1,-45} {2}' -f $mark, $c.Domain, $ips
}

Write-Host ''
if ($fail) { Write-Warning "$fail check(s) failed -- inspect https://$VMIPv4/admin" }
else       { Ok 'all checks passed' }

Write-Host @"

  VM         $VMName  ($VMIPv4 / $VMIPv6)
  Admin      https://$VMIPv4/admin
  SSH        ssh $GuestUser@$VMIPv4

  Other devices still bypass Pi-hole until the router hands out $VMIPv4 as DNS
  and stops advertising itself as an IPv6 resolver. See provision/README.md.
"@ -ForegroundColor Cyan

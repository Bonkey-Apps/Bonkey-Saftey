<#
.SYNOPSIS
    Applies the Bonkey-Saftey DNS policy pack to a Pi-hole v6 container.

.DESCRIPTION
    Registers the adlists in adlists.txt (plus this repo's own ms-game-ads.txt),
    loads lists/regex-deny.txt as regex denies and lists/allowlist.txt as exact
    allows, then rebuilds gravity.

    Everything is written straight into gravity.db via pihole-FTL sqlite3, so it
    survives container recreation as long as /etc/pihole stays bind-mounted.
    Re-running is safe -- every insert is INSERT OR IGNORE.

.PARAMETER Container
    Name of the Pi-hole Docker container. Defaults to 'pihole', matching
    docker-compose.yml in PIHOLE_DEPLOYMENT_PLAN.md.

.PARAMETER GroupOnly
    Restrict the policy to clients assigned to the 'bonkey-saftey' group instead
    of applying it to every client on the network. Off by default.

.PARAMETER SkipGravity
    Register everything but do not run 'pihole -g'. Use when staging several
    changes; gravity must be rebuilt before any of it takes effect.

.EXAMPLE
    .\install.ps1
    Apply to all clients and rebuild gravity.

.EXAMPLE
    .\install.ps1 -GroupOnly
    Apply only to clients you have put in the 'bonkey-saftey' group.
#>
[CmdletBinding()]
param(
    [string] $Container = 'pihole',
    [switch] $GroupOnly,
    [switch] $SkipGravity
)

$ErrorActionPreference = 'Stop'
$repo      = $PSScriptRoot
$groupName = 'bonkey-saftey'
$rawBase   = 'https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main'

function Assert-Container {
    $running = docker ps --filter "name=^/$Container$" --format '{{.Names}}'
    if ($running -ne $Container) {
        throw "Container '$Container' is not running. Start it, or pass -Container <name>."
    }
}

# Strips comments and blank lines from a list file.
function Read-ListFile([string] $Path) {
    if (-not (Test-Path $Path)) { throw "Missing list file: $Path" }
    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Quote([string] $Value) { "'" + $Value.Replace("'", "''") + "'" }

Assert-Container

$adlists   = @(Read-ListFile (Join-Path $repo 'adlists.txt'))
$adlists  += "$rawBase/lists/ms-game-ads.txt"
$regexes   = @(Read-ListFile (Join-Path $repo 'lists\regex-deny.txt'))
$allowed   = @(Read-ListFile (Join-Path $repo 'lists\allowlist.txt'))

Write-Host "Bonkey-Saftey -> $Container" -ForegroundColor Cyan
Write-Host ("  adlists   : {0}" -f $adlists.Count)
Write-Host ("  regex deny: {0}" -f $regexes.Count)
Write-Host ("  allowlist : {0}" -f $allowed.Count)
Write-Host ("  scope     : {0}" -f $(if ($GroupOnly) { "group '$groupName' only" } else { 'all clients' }))

$sql = [System.Collections.Generic.List[string]]::new()
$sql.Add('BEGIN TRANSACTION;')
$sql.Add("INSERT OR IGNORE INTO ""group"" (enabled, name, description) VALUES (1, $(Quote $groupName), 'Managed by Bonkey-Saftey/install.ps1 -- edits will be overwritten');")

$groupId = "(SELECT id FROM ""group"" WHERE name = $(Quote $groupName))"
# Group 0 is Pi-hole's built-in Default group: membership there means the rule
# applies to every client that has not been placed in a group of its own.
$targetGroups = if ($GroupOnly) { @($groupId) } else { @('0', $groupId) }

foreach ($url in $adlists) {
    $q = Quote $url
    $sql.Add("INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ($q, 1, 'bonkey-saftey');")
    $sql.Add("UPDATE adlist SET enabled = 1 WHERE address = $q;")
    foreach ($g in $targetGroups) {
        $sql.Add("INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, $g FROM adlist WHERE address = $q;")
    }
    if ($GroupOnly) {
        # Pi-hole's insert trigger auto-assigns new adlists to the Default
        # group; drop that so -GroupOnly really is group-scoped.
        $sql.Add("DELETE FROM adlist_by_group WHERE group_id = 0 AND adlist_id IN (SELECT id FROM adlist WHERE address = $q);")
    }
}

# domainlist.type: 0 = exact deny, 1 = exact allow, 2 = regex deny, 3 = regex allow
$entries = @()
$entries += $regexes | ForEach-Object { [pscustomobject]@{ Type = 2; Value = $_ } }
$entries += $allowed | ForEach-Object { [pscustomobject]@{ Type = 1; Value = $_ } }

foreach ($e in $entries) {
    $q = Quote $e.Value
    $sql.Add("INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES ($($e.Type), $q, 1, 'bonkey-saftey');")
    $sql.Add("UPDATE domainlist SET enabled = 1 WHERE type = $($e.Type) AND domain = $q;")
    foreach ($g in $targetGroups) {
        $sql.Add("INSERT OR IGNORE INTO domainlist_by_group (domainlist_id, group_id) SELECT id, $g FROM domainlist WHERE type = $($e.Type) AND domain = $q;")
    }
    if ($GroupOnly) {
        $sql.Add("DELETE FROM domainlist_by_group WHERE group_id = 0 AND domainlist_id IN (SELECT id FROM domainlist WHERE type = $($e.Type) AND domain = $q);")
    }
}

$sql.Add('COMMIT;')

$staged = Join-Path ([System.IO.Path]::GetTempPath()) 'bonkey-saftey.sql'
Set-Content -LiteralPath $staged -Value ($sql -join "`n") -Encoding utf8

docker cp $staged "${Container}:/tmp/bonkey-saftey.sql"
docker exec $Container pihole-FTL sqlite3 /etc/pihole/gravity.db ".read /tmp/bonkey-saftey.sql"
docker exec $Container rm -f /tmp/bonkey-saftey.sql
Remove-Item -LiteralPath $staged -Force

if ($SkipGravity) {
    Write-Host "Registered. Run 'docker exec $Container pihole -g' to apply." -ForegroundColor Yellow
} else {
    Write-Host 'Rebuilding gravity...' -ForegroundColor Cyan
    docker exec $Container pihole -g
    Write-Host 'Done.' -ForegroundColor Green
}

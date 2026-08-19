<#
.SYNOPSIS
    Removes everything install.ps1 added to a Pi-hole v6 container.

.DESCRIPTION
    Deletes every adlist and domainlist row tagged with the 'bonkey-saftey'
    comment, drops the 'bonkey-saftey' group, and rebuilds gravity. Rows you
    added by hand through the Pi-hole UI are left alone, because they do not
    carry the tag.

.PARAMETER Container
    Name of the Pi-hole Docker container. Defaults to 'pihole'.

.PARAMETER SkipGravity
    Remove the rows but do not run 'pihole -g'. Gravity still holds the old
    domains until it is rebuilt.
#>
[CmdletBinding()]
param(
    [string] $Container = 'pihole',
    [switch] $SkipGravity
)

$ErrorActionPreference = 'Stop'
$tag = 'bonkey-saftey'

$running = docker ps --filter "name=^/$Container$" --format '{{.Names}}'
if ($running -ne $Container) {
    throw "Container '$Container' is not running. Start it, or pass -Container <name>."
}

$sql = @"
BEGIN TRANSACTION;
DELETE FROM adlist_by_group     WHERE adlist_id     IN (SELECT id FROM adlist     WHERE comment = '$tag');
DELETE FROM domainlist_by_group WHERE domainlist_id IN (SELECT id FROM domainlist WHERE comment = '$tag');
DELETE FROM adlist     WHERE comment = '$tag';
DELETE FROM domainlist WHERE comment = '$tag';
DELETE FROM "group"    WHERE name    = '$tag';
COMMIT;
"@

$staged = Join-Path ([System.IO.Path]::GetTempPath()) 'bonkey-saftey-uninstall.sql'
Set-Content -LiteralPath $staged -Value $sql -Encoding utf8

docker cp $staged "${Container}:/tmp/bonkey-saftey-uninstall.sql"
docker exec $Container pihole-FTL sqlite3 /etc/pihole/gravity.db ".read /tmp/bonkey-saftey-uninstall.sql"
docker exec $Container rm -f /tmp/bonkey-saftey-uninstall.sql
Remove-Item -LiteralPath $staged -Force

if ($SkipGravity) {
    Write-Host "Removed. Run 'docker exec $Container pihole -g' to apply." -ForegroundColor Yellow
} else {
    docker exec $Container pihole -g
    Write-Host 'Removed.' -ForegroundColor Green
}

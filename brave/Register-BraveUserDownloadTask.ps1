<#
.SYNOPSIS
    Registers a Scheduled Task that runs Set-BraveUserDownloadPolicy.ps1 for
    every user at logon, so standard (non-administrator) accounts are forced
    to C:\Users\Public\Download while administrator accounts are left alone.

.DESCRIPTION
    Run this once, elevated. It registers a machine-wide Scheduled Task
    ("Brave User Download Policy") that triggers at any user's logon and
    runs with that user's own (non-elevated) identity - not SYSTEM - so that
    Set-BraveUserDownloadPolicy.ps1 correctly reads/writes the triggering
    user's own HKCU hive, and its admin-membership check reflects that
    specific account.

.NOTES
    If a task with this name already exists, its current XML definition is
    exported as a backup before being replaced.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$taskName = 'Brave User Download Policy'
$scriptPath = Join-Path $PSScriptRoot 'Set-BraveUserDownloadPolicy.ps1'

if (-not (Test-Path $scriptPath)) {
    throw "Could not find $scriptPath. Keep this script alongside Set-BraveUserDownloadPolicy.ps1."
}

# --- Backup existing task definition, if any --------------------------------
$backupDir = Join-Path $PSScriptRoot 'backups'
if (-not (Test-Path $backupDir)) {
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
}
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDir "ScheduledTask-$($taskName -replace '\s','')-Backup-$timestamp.xml"
    Export-ScheduledTask -TaskName $taskName | Out-File -FilePath $backupFile -Encoding unicode
    Write-Host "Backed up existing scheduled task definition to $backupFile" -ForegroundColor Yellow
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Fires for ANY user's interactive logon; principal below makes it run as
# the triggering user (not SYSTEM), which is required for HKCU to target
# that user's own hive.
$trigger = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Scheduled task '$taskName' registered." -ForegroundColor Green
Write-Host "It will run Set-BraveUserDownloadPolicy.ps1 as each user at their next logon." -ForegroundColor Green
Write-Host "To apply immediately without waiting for logon, run: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Green

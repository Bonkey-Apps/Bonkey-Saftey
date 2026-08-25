<#
.SYNOPSIS
    Forces a shared download folder for standard (non-administrator) Windows
    accounts only. Administrator accounts are left untouched and keep their
    normal per-profile Downloads folder.

.DESCRIPTION
    Brave's DownloadDirectory policy is normally set once under HKLM and
    applies identically to every account on the machine - there is no way to
    give admins and standard users different values from a single Mandatory
    HKLM key. To get per-account-type behavior, this script instead writes a
    per-user policy under HKCU, and only for accounts that are NOT local
    Administrators:

        HKCU\Software\Policies\BraveSoftware\Brave\DownloadDirectory
            = C:\Users\Public\Download
        HKCU\Software\Policies\BraveSoftware\Brave\PromptForDownloadLocation
            = 0

    Administrator accounts get no HKCU policy written, so Brave falls back to
    its normal per-profile Downloads folder for them.

    This script is meant to run in the CURRENT USER's own context (not
    SYSTEM) so that HKCU correctly targets that user's hive - see
    Register-BraveUserDownloadTask.ps1, which schedules this to run
    automatically at every logon.

.NOTES
    Local-admin membership is checked via ADSI group membership rather than
    the current process's token elevation state, because a standard-user
    (non-elevated) token for an admin account will NOT report
    IsInRole(Administrator) = true. Group membership is the correct test for
    "is this an administrator account," independent of whether the current
    session happens to be elevated.
#>

$ErrorActionPreference = 'Stop'

function Test-IsLocalAdministrator {
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $adminGroup = [ADSI]"WinNT://./Administrators,group"
        $members = @($adminGroup.Invoke('Members')) | ForEach-Object {
            $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
        }
        $currentSamName = ($currentUser.Name -split '\\')[-1]
        return $members -contains $currentSamName
    }
    catch {
        Write-Warning "Could not determine local admin membership ($_); assuming administrator to avoid over-restricting."
        return $true
    }
}

if (Test-IsLocalAdministrator) {
    Write-Host "Current user is a local administrator; no download-folder policy applied (using default per-profile Downloads)." -ForegroundColor Yellow
    return
}

$policyRoot = 'HKCU:\Software\Policies\BraveSoftware\Brave'
$policyRootNative = 'HKCU\Software\Policies\BraveSoftware\Brave'
$publicDownloadDir = 'C:\Users\Public\Download'

# --- Backup existing per-user policy before making any changes -------------
$backupDir = Join-Path $env:LOCALAPPDATA 'BravePolicyBackups'
if (-not (Test-Path $backupDir)) {
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
}
if (Test-Path $policyRoot) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDir "Brave-HKCU-Policy-Backup-$timestamp.reg"
    & reg.exe export $policyRootNative $backupFile /y | Out-Null
    Write-Host "Backed up existing HKCU Brave policy to $backupFile" -ForegroundColor Yellow
}

if (-not (Test-Path $publicDownloadDir)) {
    New-Item -Path $publicDownloadDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $policyRoot)) {
    New-Item -Path $policyRoot -Force | Out-Null
}

New-ItemProperty -Path $policyRoot -Name 'DownloadDirectory' -PropertyType String -Value $publicDownloadDir -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'PromptForDownloadLocation' -PropertyType DWord -Value 0 -Force | Out-Null

Write-Host "Standard-user download policy applied under $policyRoot -> $publicDownloadDir" -ForegroundColor Green

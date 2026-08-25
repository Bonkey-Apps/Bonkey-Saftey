<#
.SYNOPSIS
    Applies machine-wide Brave browser policy (HKLM) so all Windows user
    accounts on this computer get the same Brave configuration.

.DESCRIPTION
    Brave is Chromium-based and reads enterprise policy from
    HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave. Values placed
    there apply to every user profile on the machine and are locked (users
    cannot override them in brave://settings). This is the standard
    "Group Policy via registry" mechanism Brave documents for Windows.

    Run this script elevated (Administrator). Brave must be closed/restarted
    for the new policy to take effect; visit brave://policy to verify.

.NOTES
    Policy names/values verified against brave-core's own policy
    definitions (components/policy/resources/templates/policy_definitions/BraveSoftware),
    current as of Brave 141-142.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$policyRoot = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
$policyRootNative = 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'
$startupUrlsKey = Join-Path $policyRoot 'RestoreOnStartupURLs'
$urlAllowlistKey = Join-Path $policyRoot 'URLAllowlist'
$extInstallBlocklistKey = Join-Path $policyRoot 'ExtensionInstallBlocklist'
$extInstallAllowlistKey = Join-Path $policyRoot 'ExtensionInstallAllowlist'
$publicDownloadDir = 'C:\Users\Public\Download'

# --- Backup existing policy before making any changes ----------------------
$backupDir = Join-Path $PSScriptRoot 'backups'
if (-not (Test-Path $backupDir)) {
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
}
if (Test-Path $policyRoot) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDir "Brave-HKLM-Policy-Backup-$timestamp.reg"
    & reg.exe export $policyRootNative $backupFile /y | Out-Null
    Write-Host "Backed up existing HKLM Brave policy to $backupFile" -ForegroundColor Yellow
}
else {
    Write-Host "No existing HKLM Brave policy found; nothing to back up." -ForegroundColor Yellow
}

if (-not (Test-Path $policyRoot)) {
    New-Item -Path $policyRoot -Force | Out-Null
}

if (-not (Test-Path $publicDownloadDir)) {
    New-Item -Path $publicDownloadDir -ItemType Directory -Force | Out-Null
}

# --- Homepage & startup pages ---------------------------------------------
$homepageUrl = 'https://html.duckduckgo.com/html'

New-ItemProperty -Path $policyRoot -Name 'HomepageLocation' -PropertyType String -Value $homepageUrl -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'HomepageIsNewTabPage' -PropertyType DWord -Value 0 -Force | Out-Null

# RestoreOnStartup = 4 -> "Open a list of URLs" (RestoreOnStartupURLs)
New-ItemProperty -Path $policyRoot -Name 'RestoreOnStartup' -PropertyType DWord -Value 4 -Force | Out-Null
if (-not (Test-Path $startupUrlsKey)) {
    New-Item -Path $startupUrlsKey -Force | Out-Null
}
New-ItemProperty -Path $startupUrlsKey -Name '1' -PropertyType String -Value $homepageUrl -Force | Out-Null

# --- Default search engine: DuckDuckGo -------------------------------------
New-ItemProperty -Path $policyRoot -Name 'DefaultSearchProviderEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'DefaultSearchProviderName' -PropertyType String -Value 'DuckDuckGo' -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'DefaultSearchProviderKeyword' -PropertyType String -Value 'duckduckgo.com' -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'DefaultSearchProviderSearchURL' -PropertyType String -Value 'https://duckduckgo.com/?q={searchTerms}' -Force | Out-Null

# --- Disable Brave Rewards / Wallet / VPN -----------------------------------
New-ItemProperty -Path $policyRoot -Name 'BraveRewardsDisabled' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'BraveWalletDisabled' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'BraveVPNDisabled' -PropertyType DWord -Value 1 -Force | Out-Null

# --- Shields defaults: most aggressive settings exposed by policy ----------
# DefaultBraveAdblockSetting: 1=AllowAds, 2=BlockAds
New-ItemProperty -Path $policyRoot -Name 'DefaultBraveAdblockSetting' -PropertyType DWord -Value 2 -Force | Out-Null
# DefaultBraveFingerprintingV2Setting: 1=Disable, 3=Standard (strongest option Brave exposes via policy)
New-ItemProperty -Path $policyRoot -Name 'DefaultBraveFingerprintingV2Setting' -PropertyType DWord -Value 3 -Force | Out-Null
# DefaultBraveHttpsUpgradeSetting: 1=Disabled(allow HTTP), 2=Strict(require HTTPS), 3=Standard(upgrade when available)
New-ItemProperty -Path $policyRoot -Name 'DefaultBraveHttpsUpgradeSetting' -PropertyType DWord -Value 2 -Force | Out-Null

# --- Safe Browsing / phishing protection ------------------------------------
# SafeBrowsingProtectionLevel: 0=Off, 1=Standard, 2=Enhanced
New-ItemProperty -Path $policyRoot -Name 'SafeBrowsingProtectionLevel' -PropertyType DWord -Value 2 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'DisableSafeBrowsingProceedAnyway' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'SafeBrowsingExtendedReportingEnabled' -PropertyType DWord -Value 1 -Force | Out-Null

# --- Content filtering: block adult/NSFW content + force Safe Search --------
# SafeSitesFilterBehavior: 0=Off, 1=BlockMatureSites
New-ItemProperty -Path $policyRoot -Name 'SafeSitesFilterBehavior' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'ForceGoogleSafeSearch' -PropertyType DWord -Value 1 -Force | Out-Null

# Explicit allowlist so these are never caught by the content filter above
if (-not (Test-Path $urlAllowlistKey)) {
    New-Item -Path $urlAllowlistKey -Force | Out-Null
}
New-ItemProperty -Path $urlAllowlistKey -Name '1' -PropertyType String -Value 'bible.com' -Force | Out-Null
New-ItemProperty -Path $urlAllowlistKey -Name '2' -PropertyType String -Value 'www.bible.com' -Force | Out-Null

# --- Passwords & Autofill ----------------------------------------------------
New-ItemProperty -Path $policyRoot -Name 'PasswordManagerEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'AutofillCreditCardEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'AutofillAddressEnabled' -PropertyType DWord -Value 1 -Force | Out-Null

# --- Extensions: block all installs except an allowlist you maintain --------
if (-not (Test-Path $extInstallBlocklistKey)) {
    New-Item -Path $extInstallBlocklistKey -Force | Out-Null
}
New-ItemProperty -Path $extInstallBlocklistKey -Name '1' -PropertyType String -Value '*' -Force | Out-Null
if (-not (Test-Path $extInstallAllowlistKey)) {
    # Intentionally empty for now. Add approved extension IDs here later, e.g.:
    # New-ItemProperty -Path $extInstallAllowlistKey -Name '1' -PropertyType String -Value '<32-char-extension-id>' -Force | Out-Null
    New-Item -Path $extInstallAllowlistKey -Force | Out-Null
}
New-ItemProperty -Path $policyRoot -Name 'BlockExternalExtensions' -PropertyType DWord -Value 1 -Force | Out-Null
# ExtensionDeveloperModeSettings: 1=Allowed, 2=Disallowed
New-ItemProperty -Path $policyRoot -Name 'ExtensionDeveloperModeSettings' -PropertyType DWord -Value 2 -Force | Out-Null

# --- Privacy & tracking -------------------------------------------------------
New-ItemProperty -Path $policyRoot -Name 'BlockThirdPartyCookies' -PropertyType DWord -Value 1 -Force | Out-Null
# NetworkPredictionOptions: 0=Never predict/preconnect, 1=Wifi only, 2=Always
New-ItemProperty -Path $policyRoot -Name 'NetworkPredictionOptions' -PropertyType DWord -Value 0 -Force | Out-Null
# DnsOverHttpsMode "off" -> use the machine's configured local DNS resolver, not Brave's own DoH provider
New-ItemProperty -Path $policyRoot -Name 'DnsOverHttpsMode' -PropertyType String -Value 'off' -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'SpellcheckEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'SpellCheckServiceEnabled' -PropertyType DWord -Value 0 -Force | Out-Null

# --- Downloads & file safety ---------------------------------------------------
# DownloadRestrictions: 0=None, 1=Block malicious+dangerous types, 2=+uncommon, 3=Block all
New-ItemProperty -Path $policyRoot -Name 'DownloadRestrictions' -PropertyType DWord -Value 1 -Force | Out-Null

# --- Incognito / Guest mode / DevTools ----------------------------------------
# IncognitoModeAvailability: 0=Available, 1=Disabled, 2=Forced
New-ItemProperty -Path $policyRoot -Name 'IncognitoModeAvailability' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'BrowserGuestModeEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
# DeveloperToolsAvailability: 0=DisallowedForForceInstalledExtensions, 1=Allowed, 2=Disallowed
New-ItemProperty -Path $policyRoot -Name 'DeveloperToolsAvailability' -PropertyType DWord -Value 2 -Force | Out-Null
New-ItemProperty -Path $policyRoot -Name 'RemoteDebuggingAllowed' -PropertyType DWord -Value 0 -Force | Out-Null

# --- Telemetry -----------------------------------------------------------------
New-ItemProperty -Path $policyRoot -Name 'MetricsReportingEnabled' -PropertyType DWord -Value 0 -Force | Out-Null

# --- Screen capture & permission prompts ----------------------------------------
New-ItemProperty -Path $policyRoot -Name 'ScreenCaptureAllowed' -PropertyType DWord -Value 0 -Force | Out-Null
# DefaultNotificationsSetting: 1=Allow, 2=Block, 3=Ask
New-ItemProperty -Path $policyRoot -Name 'DefaultNotificationsSetting' -PropertyType DWord -Value 3 -Force | Out-Null

Write-Host "Brave machine-wide policy applied under $policyRoot" -ForegroundColor Green
Write-Host "This is Mandatory (HKLM) policy: standard users cannot change it (no HKLM write access, settings greyed out)." -ForegroundColor Green
Write-Host "Administrators can still override by editing/removing these keys from an elevated session." -ForegroundColor Green
Write-Host "Restart Brave (all users) and check brave://policy to confirm." -ForegroundColor Green

# Enable Hyper-V and Virtualization Features on Windows 11 Pro
# Run as Administrator
# Usage: Right-click PowerShell -> Run as administrator -> then run this script

# Check if running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Enabling Hyper-V and Virtualization Features" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check CPU virtualization support
Write-Host "Checking CPU virtualization support..." -ForegroundColor Yellow
$cpuInfo = Get-WmiObject -Class Win32_Processor
if ($cpuInfo.VirtualizationFirmwareEnabled -eq $true) {
    Write-Host "✓ CPU virtualization is enabled in BIOS" -ForegroundColor Green
} else {
    Write-Host "⚠ CPU virtualization may not be enabled in BIOS" -ForegroundColor Yellow
    Write-Host "   Please check BIOS settings if Hyper-V fails to enable" -ForegroundColor Yellow
}
Write-Host ""

# Enable required Windows features
Write-Host "Enabling Windows features..." -ForegroundColor Yellow

$features = @(
    "Microsoft-Hyper-V-All",
    "VirtualMachinePlatform",
    "Containers",
    "ContainersImage-oci"
)

foreach ($feature in $features) {
    Write-Host "  • Enabling $feature..." -ForegroundColor Cyan
    Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
    if ($?) {
        Write-Host "    ✓ $feature enabled" -ForegroundColor Green
    } else {
        Write-Host "    ⚠ $feature not available or already enabled" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "You MUST restart your computer for changes to take effect." -ForegroundColor Red
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart your computer now"
Write-Host "  2. After restart, verify with: wsl --version (should show version info)"
Write-Host "  3. Install Docker Desktop"
Write-Host "  4. Proceed with Pi-hole deployment"
Write-Host ""

$restart = Read-Host "Restart computer now? (y/n)"
if ($restart -eq 'y' -or $restart -eq 'Y') {
    Write-Host "Restarting in 10 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Host "Remember to restart manually before proceeding" -ForegroundColor Yellow
}

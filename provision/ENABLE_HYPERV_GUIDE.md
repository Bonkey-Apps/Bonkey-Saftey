# Enable Hyper-V and Virtualization on Windows 11 Pro

## Quick Start

After rebooting, run this script as Administrator:

```powershell
.\provision\ENABLE_HYPERV.ps1
```

(Run from the root of a `Bonkey-Saftey` checkout.)

Then restart your computer when prompted.

---

## What Gets Enabled

| Feature | Purpose |
|---------|---------|
| **Hyper-V** | Core virtualization platform for Windows |
| **Virtual Machine Platform** | Lightweight hypervisor for containers/WSL2 |
| **Containers** | Windows Container feature support |
| **Containers OCI Image** | Container image format support |

---

## Step-by-Step Instructions

### Option 1: Automated Script (Recommended)

1. Open PowerShell as Administrator
   - Click Start
   - Type `PowerShell`
   - Right-click "Windows PowerShell"
   - Select "Run as administrator"

2. Run the enable script from the root of a `Bonkey-Saftey` checkout:
   ```powershell
   .\provision\ENABLE_HYPERV.ps1
   ```

3. The script will:
   - Check CPU virtualization support
   - Enable all required Windows features
   - Prompt you to restart

4. Restart when prompted

### Option 2: Manual via Settings GUI

1. Press `Win + R`
2. Type: `optionalfeatures`
3. Click OK to open "Windows Features"
4. Check these boxes:
   - ☑ Hyper-V
   - ☑ Virtual Machine Platform
   - ☑ Containers
   - ☑ Containers-oci
5. Click OK
6. Restart when prompted

### Option 3: Manual PowerShell Commands

```powershell
# Run as Administrator

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Containers -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName ContainersImage-oci -NoRestart

# Then restart
Restart-Computer
```

---

## Prerequisites

### System Requirements

- **Windows 11 Pro** (or Enterprise/Education) ✓ You have this
- **CPU with virtualization support:**
  - Intel: VT-x (Virtualization Technology)
  - AMD: AMD-V
- **BIOS virtualization enabled** (usually enabled by default on modern systems)
- **At least 4GB RAM** (8GB+ recommended for Docker)
- **At least 2 CPU cores** (4+ recommended)

### Check if CPU Supports Virtualization

Run this in PowerShell:

```powershell
Get-WmiObject -Class Win32_Processor | Select-Object Name, VirtualizationFirmwareEnabled
```

If `VirtualizationFirmwareEnabled` shows `True`, you're good. If `False`, you may need to enable it in BIOS.

### Enable Virtualization in BIOS (if needed)

1. Restart computer
2. During startup, press the BIOS key (usually **DEL**, **F2**, **F10**, or **ESC**—check your motherboard manual)
3. Look for options like:
   - "Virtualization Technology" (Intel)
   - "SVM" or "AMD-V" (AMD)
   - "VT-d" (Intel with IOMMU)
4. Enable them
5. Save and exit

---

## After Enabling Features

### Verification

After reboot, verify everything is working:

```powershell
# Check Hyper-V is enabled
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

# Should show: State : Enabled
```

### Next Steps

1. Install Docker Desktop
   - Download from: https://www.docker.com/products/docker-desktop
   - During install, enable "Use WSL 2 instead of Hyper-V" (optional—either works)

2. Verify Docker
   ```powershell
   docker --version
   ```

3. Proceed with Pi-hole deployment (see `PIHOLE_DEPLOYMENT_PLAN.md`)

---

## Troubleshooting

### "This operation is not supported" Error

**Cause:** Your Windows edition doesn't support Hyper-V (Home edition, for example)

**Solution:** Windows 11 Pro supports Hyper-V. Verify your edition:
```powershell
Get-WmiObject Win32_OperatingSystem | Select-Object Caption
```

Should show "Windows 11 Pro"

### "Operation did not complete successfully" Error

**Cause:** Feature already enabled or BIOS virtualization disabled

**Solutions:**
1. Check if already enabled: Settings → Apps → Optional features → scroll down → look for "Hyper-V" or "Virtual Machine Platform"
2. If not shown or greyed out, enable virtualization in BIOS (see above)
3. Restart and try again

### Computer Hangs During Restart

**Cause:** First restart after enabling virtualization features can take longer

**Solution:** Wait 5-10 minutes. This is normal.

### Docker Desktop Won't Start After Enabling Hyper-V

**Cause:** Docker needs WSL 2 or Hyper-V to be properly configured

**Solution:**
```powershell
# Enable WSL 2
wsl --install

# Then restart and retry Docker
```

---

## What NOT to Do

- ❌ Don't disable Hyper-V after enabling it (breaks Docker/WSL2)
- ❌ Don't mix Hyper-V with third-party hypervisors (VirtualBox, VMware) on same machine
- ❌ Don't enable features without restarting

---

## Timeline

| Step | Time |
|------|------|
| Run enable script | 1-2 minutes |
| Windows restart | 5-10 minutes |
| Docker Desktop install | 5-10 minutes |
| Pi-hole deployment | 15-30 minutes |
| **Total** | **~30-60 minutes** |

---

## Questions?

If you run into issues:

1. Check the troubleshooting section above
2. Verify CPU virtualization is enabled in BIOS
3. Ensure you're running as Administrator
4. Check Windows 11 Pro edition is correct
5. Restart and try again

Good luck! 🚀

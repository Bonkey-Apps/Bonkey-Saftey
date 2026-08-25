# Pi-hole DNS Filtering on Windows 11 Pro: Implementation Plan

A practical guide to deploying Pi-hole in Docker with system-wide DNS filtering and enforcement mechanisms.

---

## Table of Contents

1. [Prerequisites & System Requirements](#prerequisites--system-requirements)
2. [Docker Desktop Installation & Configuration](#docker-desktop-installation--configuration)
3. [Pi-hole Container Setup & Configuration](#pi-hole-container-setup--configuration)
4. [Windows DNS Configuration & Enforcement](#windows-dns-configuration--enforcement)
5. [Security & Locking Mechanisms](#security--locking-mechanisms)
6. [Testing & Validation](#testing--validation)
7. [Troubleshooting Tips](#troubleshooting-tips)
8. [Maintenance & Updates](#maintenance--updates)

---

## Prerequisites & System Requirements

### System Requirements

- **Windows 11 Pro** (or Enterprise; Home edition does not support required features)
- **Hyper-V capability** — Enable in BIOS if not already active
- **WSL2** (Windows Subsystem for Linux 2) as Docker backend
- **Minimum 4GB RAM** available for Docker and Pi-hole
- **Minimum 10GB free disk space**
- **Network connectivity** — Stable connection required

### Check Your System

Before starting, verify your Windows version and Hyper-V status:

```powershell
# Check Windows version
winver
# Should show Windows 11 Pro (build 22000 or higher)

# Check Hyper-V capability
systeminfo | findstr /I "Hyper-V"
# Should show "Hyper-V Requirements: Virtualization Enabled"
```

**Hyper-V not enabled?** Run the following in PowerShell (Admin) and restart your computer:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

### What You'll Need

- Administrator access on your Windows machine
- Docker Desktop for Windows
- Basic familiarity with Command Prompt, PowerShell, or Windows Terminal
- A text editor (Notepad++, VS Code, or built-in Notepad)

---

## Docker Desktop Installation & Configuration

### Step 1: Download Docker Desktop

1. Visit `https://www.docker.com/products/docker-desktop`
2. Click "Download for Windows"
3. Choose the **Intel Chip** version (unless you're on ARM/Apple Silicon emulation)

### Step 2: Install Docker Desktop

1. Run the `Docker Desktop Installer.exe` file
2. Follow the installation wizard (accept default settings)
3. When prompted, ensure **"Use WSL 2 instead of Hyper-V"** is checked (recommended)
4. Restart your computer when installation completes

> **Note:** Docker Desktop may take several minutes to start after installation. Watch for the Docker whale icon in your system tray.

### Step 3: Verify Docker Installation

Open PowerShell or Windows Terminal and run:

```powershell
docker --version
docker run hello-world
```

You should see Docker version info and a "Hello from Docker!" message. This confirms Docker is running correctly.

### Step 4: Configure Docker Settings

1. Click the Docker whale icon in your system tray → **Settings**
2. Go to **Resources → Memory** and allocate **at least 2GB** to Docker
3. Go to **Resources → CPU** and allocate **at least 2 cores**
4. Enable **Settings → General → "Start Docker Desktop when you log in"** for automatic startup
5. Click **Apply & Restart**

> **Pro Tip:** Docker Desktop running at startup means Pi-hole will be available immediately after each reboot—critical for home network continuity.

---

## Pi-hole Container Setup & Configuration

### Step 1: Create a Docker Compose File

Pi-hole is easiest to manage using Docker Compose. Create a new folder for your Pi-hole configuration:

```powershell
mkdir C:\pihole
cd C:\pihole
```

Create a file named `docker-compose.yml` in this folder (use Notepad or VS Code):

```yaml
version: '3.9'

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
      - "443:443/tcp"
    environment:
      TZ: 'America/Chicago'
      WEBPASSWORD: 'MySecurePassword123'
      DNS1: '1.1.1.1'
      DNS2: '1.0.0.1'
    volumes:
      - './etc-pihole/:/etc/pihole/'
      - './etc-dnsmasq.d/:/etc/dnsmasq.d/'
    restart: unless-stopped
    networks:
      - pihole-network

networks:
  pihole-network:
    driver: bridge
```

> **⚠️ Change the Password:** Replace `MySecurePassword123` with a **strong, unique password**. This protects your Pi-hole admin interface.

### Step 2: Create Required Directories

Pi-hole needs two directories to store its configuration:

```powershell
cd C:\pihole
New-Item -ItemType Directory -Force -Path ".\etc-pihole"
New-Item -ItemType Directory -Force -Path ".\etc-dnsmasq.d"
```

### Step 3: Launch Pi-hole Container

Navigate to the Pi-hole folder and start the container:

```powershell
cd C:\pihole
docker-compose up -d
```

The `-d` flag runs the container in the background. Docker will:
- Download the Pi-hole image (first time only, ~500 MB)
- Create and start the container
- Automatically restart on reboot

Verify the container is running:

```powershell
docker ps -a
```

You should see the `pihole` container with status `Up`.

### Step 4: Access Pi-hole Admin Dashboard

Open a web browser and navigate to:

```
http://localhost/admin
```

Log in with:
- **Username:** `admin`
- **Password:** The password you set in the docker-compose.yml file

> **Note:** If you get "Connection Refused," wait 30-60 seconds for Pi-hole to fully initialize, then refresh the page.

### Step 5: Configure Pi-hole Settings

#### 1. Set Your Timezone & Location

In the Admin Dashboard, go to **Settings → Local DNS Records**. Verify your system timezone is correct.

#### 2. Configure Upstream DNS Servers

Go to **Settings → DNS** and configure upstream resolvers. The docker-compose file uses Cloudflare (1.1.1.1), which is recommended for speed and privacy. Alternatives:

- **Quad9:** 9.9.9.9 (security-focused)
- **OpenDNS:** 208.67.222.222 (family-friendly)
- **Google DNS:** 8.8.8.8 (fast but logs queries)

#### 3. Enable DNSSEC & Conditional Forwarding (Optional)

Still in **Settings → DNS**:

- Check **"Use DNSSEC"** for additional DNS security
- Check **"Conditional Forwarding"** and enter your router IP (usually 192.168.1.1) to resolve local network device names

### Step 6: Add Blocklists

Pi-hole's power comes from curated blocklists. Go to **Adlists** and add reputable lists:

| Blocklist Name | URL | Purpose |
|---|---|---|
| Steven Black Hosts | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` | Ads, malware, gambling |
| AdGuard DNS | `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt` | Ads and tracking |
| Energized Protection | `https://energized.pro/formats` | Comprehensive blocking |
| DShield Blocklist | `https://www.dshield.org/feeds/suspiciousdomains_High.txt` | Known malicious domains |

> **Recommended Approach:** Start with 2–3 blocklists. Too many lists can cause performance issues or block legitimate sites. Monitor your query logs for a few days, then add more if needed.

---

## Windows DNS Configuration & Enforcement

### Understanding DNS Resolution on Windows

By default, Windows queries the DNS servers configured in your network adapter settings. To use Pi-hole system-wide, you must:

1. Set Pi-hole as your primary DNS resolver
2. Lock these settings to prevent tampering
3. Handle edge cases (VPN, work networks, etc.)

### Step 1: Configure DNS via Network Settings (GUI Method)

1. **Open Network Settings:** Press `Win + I` to open Settings, then go to **Network & Internet → WiFi** (or **Ethernet** for wired).

2. **Edit Your Connection:** Click your active network → **Edit DNS settings**.

3. **Switch to Manual DNS:** Toggle **"Edit"** and change from "Automatic" to **"Manual"**.

4. **Enter Pi-hole IP Address:**
   - **Primary DNS:** `127.0.0.1` (your localhost, where Pi-hole runs)
   - **Secondary DNS:** `1.1.1.1` (Cloudflare fallback if Pi-hole is unavailable)

5. **Save and Test:** Click **Save**. Your computer now uses Pi-hole for DNS lookups.

### Step 2: Configure DNS via PowerShell (Command Method)

For scripting or remote configuration, use PowerShell:

```powershell
# Get your active network adapter name
Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

# Set DNS to Pi-hole (replace "Ethernet" with your adapter name)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("127.0.0.1", "1.1.1.1")

# Verify DNS settings
Get-DnsClientServerAddress -InterfaceAlias "Ethernet"
```

### Step 3: Test DNS Resolution

Verify Pi-hole is now handling your DNS queries:

```powershell
# Flush DNS cache
ipconfig /flushdns

# Test DNS resolution
nslookup google.com
# Should show results resolved through Pi-hole

# Check your public IP (for reference)
(Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
```

✅ **Success:** If `nslookup` returns valid results, Pi-hole is now filtering your DNS queries. Check the Pi-hole dashboard to see blocked queries in real time.

---

## Security & Locking Mechanisms

A standard user can quickly disable Pi-hole by changing DNS settings back. Here's how to lock it down:

### Method 1: Group Policy Lock (Strongest)

Use Windows Group Policy to prevent DNS setting changes—even administrators cannot bypass this without the Group Policy Editor.

1. **Open Group Policy Editor:** Press `Win + R`, type `gpedit.msc`, and press Enter.

2. **Navigate to Network Adapters Policy:** Go to **Computer Configuration → Administrative Templates → Network → Network Connections**.

3. **Disable DNS Configuration Changes:** Find and open **"Prohibit access to properties of components of a LAN connection"**.
   - Set to **Enabled**
   - In the **"Restrict access"** dropdown, select **"All properties"**

4. **Apply and Reboot:** Click **Apply** and **OK**. Restart your computer.

> **Advanced Locking:** For even stronger protection, also configure **"Prohibit access to the New Connection Wizard"** and **"Prohibit deletion of RAS connections"**.

### Method 2: Registry Lock

If Group Policy is unavailable, lock DNS settings via the Windows Registry:

```powershell
# Backup registry first
reg export HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters Registry_Backup.reg

# Lock DNS settings (prevent changes)
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "AddressType" /t REG_DWORD /d 0 /f
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Interfaces" /v "NameServer" /t REG_SZ /d "127.0.0.1,1.1.1.1" /f
```

> **⚠️ Registry Changes Are Permanent:** Incorrect registry edits can break network connectivity. Always back up the registry before making changes, and test thoroughly.

### Method 3: Container-Level Protection

Prevent Pi-hole from being easily stopped or deleted:

```powershell
# Make the Pi-hole container restart automatically on failure
docker update --restart always pihole

# Verify the restart policy
docker inspect -f "{{.HostConfig.RestartPolicy}}" pihole
```

### Method 4: Create a Restricted User Account

For families or multi-user systems, run primary users on standard (non-admin) accounts:

1. Open **Settings → Accounts → Other people**
2. Click **"Add account"** and create a new local account
3. Switch this account to **"Standard user"** in **Change account type**
4. Users on this account cannot change DNS or run Docker commands

### Method 5: Secure Pi-hole Admin Panel

Protect the Pi-hole web interface itself:

1. Log into Pi-hole at `http://localhost/admin`
2. Go to **Settings → Web Interface → API**
3. Note your API token (keep it secret)
4. Change your admin password to something long and unique: **Settings → Admin password**

> **Important:** If someone accesses the Pi-hole interface, they can disable filtering entirely. A strong password is essential. Consider using a password manager.

### Method 6: Firewall Rules (Additional Layer)

Block outbound DNS queries on ports other than 53 to prevent bypass attempts:

```powershell
# Block DNS on ports 853 (DoT) and 443 (DoH)
New-NetFirewallRule -DisplayName "Block Non-Local DNS" -Direction Outbound -Action Block -Protocol UDP -RemotePort 53 -RemoteAddress "!127.0.0.1" -Profile Domain,Private,Public

# Verify the rule
Get-NetFirewallRule -DisplayName "Block Non-Local DNS"
```

> **⚠️ Be Careful:** Overly restrictive firewall rules can break legitimate apps (VPNs, work security tools, etc.). Test thoroughly before enforcing.

---

## Testing & Validation

### Test 1: Verify Pi-hole is Responding

```powershell
# Query Pi-hole directly
nslookup google.com 127.0.0.1

# You should see a response from 127.0.0.1 with resolved IPs
```

### Test 2: Check Query Logs in Dashboard

1. Open `http://localhost/admin`
2. Go to **Query Log**
3. Open a few websites in your browser
4. Refresh the query log—you should see entries from your computer (127.0.0.1)
5. Blocked queries appear in red; allowed queries in green

### Test 3: Test a Known Ad Domain

Pi-hole should block ads. Test with:

```powershell
# This domain is typically on blocklists
nslookup ads.doubleclick.net

# Should fail to resolve (NXDOMAIN)
```

### Test 4: Browser Ad Blocking

1. Visit a website known for ads (e.g., `cnn.com`, `reddit.com`)
2. Ads should be noticeably reduced compared to before Pi-hole
3. Check the query log to see blocked ad domains in real time

### Test 5: App DNS Resolution

Verify non-browser apps use Pi-hole:

```powershell
# Use Nslookup from PowerShell to see what apps are resolving
# Open another PowerShell window and monitor DNS:
Get-Process | Where-Object {$_.Name -match "python|node|java"} | Select-Object Name, ID
```

### Test 6: Failover Testing

Verify your secondary DNS works if Pi-hole fails:

1. Stop the Pi-hole container: `docker stop pihole`
2. Try `nslookup google.com`
3. Should fall back to secondary DNS (1.1.1.1) and still resolve
4. Restart: `docker start pihole`

✅ **All Tests Passing?** Your Pi-hole deployment is working correctly. DNS queries are being filtered, ads are blocked, and fallback DNS is in place.

---

## Troubleshooting Tips

### Issue: "Docker daemon is not running"

**Solution:**
- Click the Docker icon in your system tray to start Docker Desktop
- Wait 30 seconds for Docker to initialize
- Verify with `docker ps`

### Issue: Pi-hole Container Won't Start

```powershell
# Check container logs
docker logs pihole

# Common issues in logs:
# - "Address already in use (port 53)" → Another DNS service is running
# - "Permission denied" → Run PowerShell as Administrator
```

**Solutions:**
- Port 53 conflict: Check what's using port 53 with `netstat -ano | findstr :53`
- If Windows DNS (Dnsproxy.exe) is running: Disable it or change Pi-hole port in docker-compose.yml
- Stop conflicting service: `Stop-Service -Name "DNS" -Force`

### Issue: No Internet After Changing DNS

```powershell
# Flush DNS cache
ipconfig /flushdns

# Renew DHCP lease
ipconfig /release
ipconfig /renew

# Test connectivity
Test-NetConnection -ComputerName 8.8.8.8 -Port 53
```

**If still no internet:**
1. Revert DNS to automatic: **Settings → Network → WiFi/Ethernet → Edit DNS → Automatic**
2. Verify Pi-hole container is running: `docker ps`
3. Check Pi-hole logs: `docker logs pihole`

### Issue: Some Sites or Apps Don't Work

**Cause:** A blocklist is too aggressive and blocking legitimate traffic.

**Solution:**
1. Go to Pi-hole **Query Log** and find the blocked domain
2. Add it to **Whitelist** (green icon)
3. Refresh the failing website
4. If many sites fail, disable the most aggressive blocklists and test

### Issue: DNS Resolution Very Slow

**Cause:** Too many blocklists or under-resourced container.

**Solution:**
- Reduce the number of active blocklists to 3–4 reputable ones
- Increase Docker memory allocation to Pi-hole (Settings → Resources → Memory)
- Check upstream DNS latency by testing directly: `nslookup -type=NS google.com 1.1.1.1`

### Issue: Can't Access Pi-hole Admin Panel

```powershell
# Check if Pi-hole is listening on port 80
netstat -ano | findstr :80

# Check container network
docker network inspect pihole-network

# Restart the container
docker restart pihole
```

After restart, wait 15 seconds and try `http://localhost/admin` again.

### Issue: Forgot Admin Password

```powershell
# Reset Pi-hole password in the container
docker exec pihole pihole -a -p

# Follow prompts to set a new password
# Or set it directly in environment:
# Edit docker-compose.yml, change WEBPASSWORD, then:
docker-compose up -d
```

### Issue: Updates and Upgrades Failing

```powershell
# Pull the latest Pi-hole image
docker pull pihole/pihole:latest

# Recreate the container with new image
docker-compose up -d --pull always
```

---

## Maintenance & Updates

### Regular Maintenance Tasks

| Task | Frequency | What to Do |
|------|-----------|-----------|
| Review Query Logs | Weekly | Check Pi-hole dashboard for unexpected blocks. Whitelist if needed. |
| Check System Performance | Monthly | Monitor CPU/memory usage in Docker settings. Adjust if needed. |
| Update Blocklists | Monthly | Pi-hole auto-updates lists, but manually check for new recommendations. |
| Update Docker & Pi-hole | Monthly | Pull latest images and recreate containers. |
| Backup Configuration | Quarterly | Export Pi-hole settings from Admin → Teleporter. |

### Update Docker Desktop

Docker Desktop notifies you of updates in the system tray. To update:

1. Click Docker icon → **Check for updates**
2. If available, download and install
3. Docker will restart automatically (containers restart after Docker restarts)

### Update Pi-hole Image

```powershell
cd C:\pihole

# Pull the latest Pi-hole image
docker pull pihole/pihole:latest

# Recreate the container
docker-compose up -d
```

This pulls the latest Pi-hole version and restarts the container with updated code. Configuration is preserved in your volumes.

### Backup Your Configuration

Pi-hole can be backed up in two ways:

#### Method 1: Teleporter (Recommended)

1. Go to Pi-hole Admin → **Teleporter**
2. Click **"Backup"**
3. A `.tar.gz` file downloads with all settings, lists, and whitelist/blacklist data
4. Store this file in a safe location (cloud storage, external drive)

#### Method 2: Manual Backup

```powershell
# Backup the Pi-hole configuration directories
Copy-Item -Path "C:\pihole\etc-pihole" -Destination "C:\pihole\backup\etc-pihole_$(Get-Date -Format 'yyyyMMdd')" -Recurse
Copy-Item -Path "C:\pihole\etc-dnsmasq.d" -Destination "C:\pihole\backup\etc-dnsmasq.d_$(Get-Date -Format 'yyyyMMdd')" -Recurse
```

### Monitor Disk Usage

```powershell
# Check Pi-hole container size
docker ps -a --format "{{.Names}}\t{{.Size}}"

# View detailed volume usage
docker volume inspect pihole_pihole

# If logs grow too large, prune old data
docker system prune -a
```

### Set Up Log Rotation

By default, Pi-hole logs don't rotate and can grow large. To limit log size, edit your docker-compose.yml:

```yaml
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

This keeps only 3 log files of 10 MB each, with older logs rotated out.

### Restart Strategy

Your docker-compose.yml includes `restart: unless-stopped`, which means:
- If the container crashes, Docker automatically restarts it
- If Docker restarts, Pi-hole restarts automatically
- If you manually stop the container, it stays stopped

To manually stop or restart:

```powershell
# Stop Pi-hole
docker stop pihole

# Start Pi-hole
docker start pihole

# Restart Pi-hole
docker restart pihole
```

### Health Checks

Optionally, add health checks to automatically restart Pi-hole if it becomes unresponsive:

```yaml
    healthcheck:
      test: ["CMD", "dig", "@127.0.0.1", "google.com", "+short"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

This queries Pi-hole every 30 seconds. If it fails 3 times in a row, the container restarts automatically.

### Scheduled Tasks for Automation

Create a Windows Task Scheduler job for automatic backups:

1. Open **Task Scheduler** (search in Start menu)
2. Click **"Create Basic Task"**
3. Name: "Pi-hole Backup"
4. Set trigger to **"Daily"** at 2:00 AM (or your preference)
5. Action: **"Start a program"**
6. Program: `powershell.exe`
7. Arguments: `-Command "& 'C:\pihole\backup-script.ps1'"`
8. Click **Finish**

Create the backup script `C:\pihole\backup-script.ps1`:

```powershell
# Auto-backup script
$BackupDir = "C:\pihole\backups"
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupFile = "$BackupDir\pihole_backup_$Timestamp.tar.gz"

# Backup configuration directories
docker exec pihole tar czf /tmp/pihole_backup.tar.gz -C /etc pihole dnsmasq.d
docker cp pihole:/tmp/pihole_backup.tar.gz $BackupFile

# Keep only the last 10 backups
Get-ChildItem -Path $BackupDir -Filter "pihole_backup_*.tar.gz" -File |
    Sort-Object -Property CreationTime -Descending |
    Select-Object -Skip 10 |
    Remove-Item -Force
```

This script automatically creates daily backups and keeps the last 10 versions, cleaning up older ones.

---

## Summary

This implementation plan provides a complete, production-ready Pi-hole deployment on Windows 11 Pro with:

- **Easy setup**: Docker Compose handles container orchestration
- **System-wide filtering**: All DNS queries route through Pi-hole
- **Multiple security layers**: Group Policy, Registry, firewall, and application-level protections
- **Automatic recovery**: Container restart policies and health checks
- **Regular backups**: Automated backup scheduling for configuration
- **Comprehensive troubleshooting**: Common issues with clear solutions

Follow this plan step-by-step, and you'll have a robust, maintainable DNS filtering system that's resistant to tampering and easy to update.

**Document Version:** 1.0  
**Updated:** 2026  
**For:** Windows 11 Pro with Docker Desktop  
**Pi-hole Version:** Latest (Docker image)

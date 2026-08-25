# Complete Pi-hole Deployment Guide for Windows 11 Pro

## Overview

This guide walks you through the complete installation process:

1. **Enable Hyper-V** (virtualization support)
2. **Install Docker Desktop** (container platform)
3. **Deploy Pi-hole** (DNS filtering)
4. **Enforce DNS** (prevent bypass)

**Estimated total time: 45-90 minutes**

---

## Phase 1: Enable Hyper-V (5-15 minutes)

### Prerequisites
- Windows 11 Pro (confirmed ✓)
- CPU with virtualization support
- Administrator access
- ~30GB free disk space

### Step 1: Run Hyper-V Enablement Script

Open PowerShell as Administrator:

1. Press `Win + X`
2. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
3. Run:
   ```powershell
   C:\Users\famla\Documents\Git\bonkey-apps\ENABLE_HYPERV.ps1
   ```

4. The script will:
   - Check CPU virtualization support
   - Enable Hyper-V and Virtual Machine Platform
   - Enable Container features
   - Prompt you to restart

5. **Restart your computer when prompted**

### Step 2: Verify Hyper-V is Enabled

After restart, open PowerShell and run:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Select-Object State
```

Should show: `State : Enabled`

### Troubleshooting

**Problem:** "This operation is not supported"
- **Solution:** Check Windows edition: `winver` should show "Windows 11 Pro"

**Problem:** CPU virtualization support message
- **Solution:** Restart and enter BIOS to enable VT-x or AMD-V

**Problem:** Computer hangs during restart
- **Solution:** Wait 10+ minutes on first restart (this is normal)

---

## Phase 2: Install Docker Desktop (10-20 minutes)

### Step 1: Run Docker Installation Script

Open PowerShell as Administrator and run:

```powershell
C:\Users\famla\Documents\Git\bonkey-apps\INSTALL_DOCKER.ps1
```

The script will:
- Verify Hyper-V is enabled
- Download Docker Desktop installer
- Install Docker silently
- Configure WSL2 backend
- Verify installation with `hello-world` container
- Guide you to next steps

**The first installation may take 5-10 minutes. DO NOT close the window.**

### Step 2: Verify Docker Installation

Close and reopen PowerShell as Administrator, then run:

```powershell
docker --version
docker ps
```

Should show Docker version and an empty container list (no errors).

### Step 3: Test Docker is Working

```powershell
docker run hello-world
```

Should display a "Hello from Docker!" message.

### Troubleshooting

**Problem:** "Docker daemon is not running"
- **Solution:** Docker Desktop starts automatically. Wait 30 seconds and try again.

**Problem:** "Docker not found in PATH"
- **Solution:** Close and reopen PowerShell completely (or run `refreshenv`)

**Problem:** Installation fails with error code
- **Solution:** 
  - Restart computer
  - Ensure Hyper-V is enabled (Phase 1)
  - Try manual download: https://www.docker.com/products/docker-desktop/

---

## Phase 3: Deploy Pi-hole (15-30 minutes)

### Step 1: Verify Prerequisites

Before deploying, ensure:
- ✓ Hyper-V is enabled
- ✓ Docker Desktop is installed and running
- ✓ You're in the working directory: `C:\Users\famla\Documents\Git\bonkey-apps`

Check in PowerShell:
```powershell
docker ps
```

Should work without errors.

### Step 2: Run Pi-hole Deployment Script

Open PowerShell as Administrator and run:

```powershell
C:\Users\famla\Documents\Git\bonkey-apps\DEPLOY_PIHOLE.ps1
```

The script will:
- Create Pi-hole data directories
- Pull the latest Pi-hole image from Docker Hub (~150MB, takes 2-5 min)
- Start Pi-hole and dnsmasq containers
- Configure Windows DNS to use localhost (127.0.0.1)
- Apply Windows Firewall rules to enforce Pi-hole usage
- Configure Registry policies
- Test DNS resolution
- Display access information

**This is the critical step. Do not interrupt it.**

### Step 3: Verify Pi-hole is Running

After the script completes, run:

```powershell
docker ps
```

Should show two containers running:
- `pihole` — Main DNS filtering engine
- `dnsmasq` — Local DNS caching

### Step 4: Access Pi-hole Admin Panel

1. Open browser: `http://127.0.0.1/admin` or `http://localhost/admin`
2. Login with:
   - **Username:** `admin`
   - **Password:** `[REDACTED]`

3. **IMMEDIATELY change the password:**
   - Click Settings (gear icon)
   - Click "Admin" → "Password"
   - Enter new password
   - Save

### Step 5: Configure Blocklists

1. In admin panel, go to **Adlists**
2. Add common blocklists (optional, Pi-hole comes with defaults):
   - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` (Steve Black's list)
   - `https://winhelp2002.mvps.org/hosts.txt` (MVPS hosts)
   - Custom enterprise blocklists

3. Gravity will update (takes ~30 seconds)

### Troubleshooting

**Problem:** Cannot access admin panel
- **Solution:** Wait 15 seconds for Pi-hole to fully start, then refresh browser

**Problem:** DNS not resolving
- **Solution:** 
  ```powershell
  nslookup google.com 127.0.0.1
  ```
  If this fails, check Docker logs:
  ```powershell
  docker-compose logs pihole
  ```

**Problem:** "Connection refused" error
- **Solution:** Pi-hole is still starting. Wait 30 seconds and refresh.

**Problem:** Container keeps stopping
- **Solution:** Check logs for errors:
  ```powershell
  docker logs pihole
  ```

---

## Phase 4: Enforce DNS (All Users Must Use Pi-hole)

### What Gets Enforced

The deployment script automatically:

1. **Sets Windows DNS** to localhost (127.0.0.1)
2. **Blocks direct DNS** via Windows Firewall:
   - Outbound port 53 (TCP/UDP) blocked
   - Only Pi-hole can receive DNS
3. **Configures Registry** to discourage DNS override
4. **Blocks DoH bypass** by restricting HTTPS DNS services

### Testing Enforcement

#### Test 1: DNS Resolution

```powershell
nslookup google.com
```

Should show: `127.0.0.1` (your local Pi-hole)

#### Test 2: Verify Firewall Blocks Direct DNS

```powershell
# This should fail
nslookup google.com 8.8.8.8
```

Should get "timeout" or "connection refused" (expected—enforcement working)

#### Test 3: Check Query Logs

1. Open admin panel: `http://127.0.0.1/admin`
2. Go to **Query Log**
3. Should see DNS queries coming from `127.0.0.1` or `localhost`

#### Test 4: Test Ad Blocking

1. Visit a site with ads: `https://example.com`
2. Check admin panel → **Query Log**
3. Should see blocked ad domains (marked with ⛔)

### Verify for Regular Users

As a regular (non-admin) user:

```powershell
nslookup google.com
```

Should still work and show `127.0.0.1` (they cannot bypass)

Try to change DNS:
- Settings → Network & Internet → Change adapter options
- Right-click adapter → Properties
- Should not be able to change DNS (if Registry policy applied)

---

## Post-Deployment: Maintenance

### Daily

- Check admin panel for unusual query patterns
- Monitor blocked queries

### Weekly

- Review blocklist effectiveness
- Check for false positives

### Monthly

- Update Docker images:
  ```powershell
  docker pull pihole/pihole:latest
  docker-compose up -d
  ```

- Review and update blocklists

### Troubleshooting Commands

```powershell
# View container status
docker ps -a

# View logs
docker-compose logs -f pihole

# Restart containers
docker-compose restart

# Stop containers
docker-compose down

# Start containers
docker-compose up -d

# Full rebuild
docker-compose pull pihole/pihole:latest
docker-compose up -d --force-recreate

# Access Pi-hole shell
docker exec -it pihole bash

# Test DNS from within container
docker exec pihole dig google.com
```

---

## Files Included

| File | Purpose |
|------|---------|
| `ENABLE_HYPERV.ps1` | Enable virtualization features |
| `INSTALL_DOCKER.ps1` | Download and install Docker |
| `docker-compose.yml` | Pi-hole container configuration |
| `DEPLOY_PIHOLE.ps1` | Main deployment script |
| `PIHOLE_DEPLOYMENT_PLAN.md` | Detailed architectural plan |
| `DEPLOYMENT_GUIDE.md` | This file |

---

## Summary of Enforcement

### How Users Are Forced Through Pi-hole

| Layer | Method | Bypass Difficulty |
|-------|--------|-------------------|
| DNS Settings | Set to localhost | Requires admin + Registry unlock |
| Firewall Rules | Port 53 blocked | Requires firewall disabled (admin) |
| Registry Policy | DNS path restricted | Requires policy removal (admin) |
| Container | Always running | Requires stopping container (admin) |
| Startup | Auto-restart on boot | Requires disabling service (admin) |

**Result:** Regular users cannot bypass. Even local admins need multiple steps to disable enforcement.

---

## Security Notes

### Passwords

- **Change the Pi-hole admin password immediately** after deployment
- This password protects the filtering configuration
- Consider a strong passphrase (20+ characters)

### Firewall

- The deployed firewall rules enforce DNS through Pi-hole
- Be cautious removing these rules unless you intend to allow direct DNS

### Network

- Pi-hole only listens on localhost (`127.0.0.1`)
- Cannot be accessed from other devices (by design—use for single machine)
- For network-wide Pi-hole, would need different configuration

### Updates

- Docker images update regularly—run monthly updates
- Test updates on a non-production system first if critical
- Keep blocklists current for best filtering

---

## Quick Reference

### Access Pi-hole
```
http://127.0.0.1/admin
```

### View Logs
```powershell
docker-compose logs -f pihole
```

### Restart Everything
```powershell
docker-compose restart
```

### Check Status
```powershell
docker ps
```

---

## Support & Troubleshooting

### Common Issues

**"Firewall rule already exists"**
- The script handles this. Existing rules are updated.

**"Port 53 already in use"**
- Another DNS service is running. Stop it or use different port.

**"Docker containers won't start"**
- Check available disk space: need ~3-5GB free

**"DNS resolution slow"**
- Pi-hole may be processing blocklists. Wait 2-3 minutes.

### Getting Help

1. Check admin panel → **Tools** → **Diagnostics**
2. Review Docker logs: `docker-compose logs pihole`
3. Verify firewall rules: `Get-NetFirewallRule | grep DNS`
4. Check DNS config: `Get-DnsClientServerAddress`

---

## Next Steps After Deployment

1. ✅ Access admin panel and change password
2. ✅ Configure blocklists to your preferences
3. ✅ Test enforcement (run the verification tests above)
4. ✅ Monitor query logs for a few days
5. ✅ Fine-tune whitelists/blacklists as needed
6. ✅ Schedule monthly update/maintenance

---

**Deployment complete! Pi-hole is now your network's DNS filter.** 🎉

For detailed architectural information, see: `PIHOLE_DEPLOYMENT_PLAN.md`

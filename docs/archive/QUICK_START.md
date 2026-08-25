# Quick Start: Pi-hole Deployment Checklist

Run these scripts in order after each system reboot.

---

## ✅ Phase 1: Enable Virtualization (Do Once)

**Timeline: 5-15 minutes + restart**

```powershell
# Open PowerShell as Administrator, then run:
C:\Users\famla\Documents\Git\bonkey-apps\ENABLE_HYPERV.ps1
```

**What it does:**
- Enables Hyper-V features
- Enables Virtual Machine Platform
- Enables Container support
- Prompts to restart

**After restart:** Proceed to Phase 2

---

## ✅ Phase 2: Install Docker (Do Once)

**Timeline: 10-20 minutes**

```powershell
# Open PowerShell as Administrator, then run:
C:\Users\famla\Documents\Git\bonkey-apps\INSTALL_DOCKER.ps1
```

**What it does:**
- Verifies Hyper-V is enabled
- Downloads Docker Desktop
- Installs Docker silently
- Tests Docker with hello-world
- Displays next steps

**After install:** Proceed to Phase 3

---

## ✅ Phase 3: Deploy Pi-hole (Do Once)

**Timeline: 15-30 minutes**

```powershell
# Open PowerShell as Administrator, then run:
C:\Users\famla\Documents\Git\bonkey-apps\DEPLOY_PIHOLE.ps1
```

**What it does:**
- Creates Pi-hole directories
- Pulls Pi-hole image
- Starts containers
- Sets Windows DNS to localhost
- Configures firewall rules
- Locks Registry settings
- Tests DNS
- Shows access info

**After deploy:** Proceed to Configuration

---

## ⚙️ Phase 4: Configure Pi-hole (Do Once)

**Timeline: 5 minutes**

1. **Access admin panel:**
   ```
   http://127.0.0.1/admin
   ```

2. **Login:**
   - Username: `admin`
   - Password: `[REDACTED]`

3. **Change password immediately:**
   - Settings (gear icon) → Admin → Password
   - Enter strong password
   - Save

4. **Optional: Add blocklists**
   - Adlists → Add new
   - Paste blocklist URL
   - Save

5. **Verify it's working:**
   - Query Log → Should see blocked ads
   - Test: Visit `https://example.com` → Check logs

---

## 🧪 Phase 5: Verify Enforcement

**Timeline: 5 minutes**

### Test 1: DNS Using Pi-hole
```powershell
nslookup google.com
# Should show: 127.0.0.1
```

### Test 2: Direct DNS Blocked
```powershell
nslookup google.com 8.8.8.8
# Should timeout (enforcement working ✓)
```

### Test 3: Ad Blocking Works
1. Visit any website with ads
2. Check admin panel → Query Log
3. Should see blocked ad domains (⛔)

### Test 4: Regular User Cannot Bypass
1. Log in as regular (non-admin) user
2. Try: `nslookup google.com`
3. Should still show 127.0.0.1 (cannot bypass ✓)

---

## 📋 Maintenance Checklist

### Weekly
- [ ] Check admin panel for unusual patterns
- [ ] Review blocked queries
- [ ] Verify DNS is resolving correctly

### Monthly
- [ ] Update Pi-hole:
  ```powershell
  docker pull pihole/pihole:latest
  docker-compose up -d
  ```
- [ ] Review blocklists
- [ ] Check for false positives

### As Needed
- [ ] Add domains to whitelist (false positives)
- [ ] Add domains to blacklist (missed ads)
- [ ] Adjust Pi-hole settings

---

## 🔧 Common Commands

### View Status
```powershell
docker ps
```

### View Logs
```powershell
docker-compose logs -f pihole
```

### Stop Everything
```powershell
docker-compose down
```

### Start Everything
```powershell
docker-compose up -d
```

### Restart Everything
```powershell
docker-compose restart
```

### Access Pi-hole Shell
```powershell
docker exec -it pihole bash
```

### Update Everything
```powershell
docker pull pihole/pihole:latest
docker-compose up -d --force-recreate
```

---

## 🆘 Emergency: Disable Pi-hole

If you need to temporarily disable Pi-hole filtering:

```powershell
# Stop containers
docker-compose down

# Change DNS back to automatic
# Settings → Network & Internet → Change adapter options
# Right-click adapter → Properties → IPv4 Properties
# Set to "Obtain DNS server address automatically"
```

To re-enable:
```powershell
docker-compose up -d
```

---

## 📍 File Locations

| File | Purpose |
|------|---------|
| `ENABLE_HYPERV.ps1` | Virtualization setup |
| `INSTALL_DOCKER.ps1` | Docker installation |
| `DEPLOY_PIHOLE.ps1` | Pi-hole deployment |
| `docker-compose.yml` | Container config |
| `pihole/` | Pi-hole data directory |
| `DEPLOYMENT_GUIDE.md` | Full documentation |
| `PIHOLE_DEPLOYMENT_PLAN.md` | Architecture details |

---

## 🎯 Success Criteria

- ✅ Docker containers running (`docker ps` shows pihole + dnsmasq)
- ✅ DNS resolves to 127.0.0.1 (`nslookup google.com`)
- ✅ Direct DNS is blocked (`nslookup google.com 8.8.8.8` fails)
- ✅ Admin panel accessible (`http://127.0.0.1/admin`)
- ✅ Query log shows activity
- ✅ Ads are being blocked (visible in query log)
- ✅ Regular users cannot change DNS settings

---

## 📞 Support

For detailed help, see:
- **Full Guide:** `DEPLOYMENT_GUIDE.md`
- **Architecture:** `PIHOLE_DEPLOYMENT_PLAN.md`
- **Specific Issue:** See troubleshooting in DEPLOYMENT_GUIDE.md

---

**All scripts are in: `C:\Users\famla\Documents\Git\bonkey-apps`**

**Estimated total time (one-time setup): 1-2 hours**

Good luck! 🚀

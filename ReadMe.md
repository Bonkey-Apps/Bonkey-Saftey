# Bonkey-Saftey

DNS policy pack for the household Pi-hole. Blocks the advertising shown inside
Microsoft's built-in games — Solitaire Collection, Mahjong, Minesweeper, Jigsaw,
Sudoku, Ultimate Word Games — with particular attention to the gambling and
casino creatives those games serve to a logged-in kid account.

Plain text lists installed by URL subscription. They run on the Pi-hole v6 VM
at `10.77.77.10` — see `provision/` to rebuild that server from scratch.

## What is in here

| File | Role |
|---|---|
| `adlists.txt` | Third-party adlist URLs to register with Pi-hole. |
| `lists/ms-game-ads.txt` | Our own hosts-format list — the MSN ad broker and the ad networks the Casual Games suite pulls video interstitials from. |
| `lists/ad-networks.txt` | ABP-syntax block list covering those same ad networks at whole-domain level, so new vendor subdomains are caught without edits. |
| `provision/` | Scripts that rebuild the Pi-hole VM these lists run on, and undo that rebuild. |
| `lists/allowlist.txt` | Exact allows that override the broad third-party lists. **Do not prune this to tighten filtering** — every entry breaks something if blocked. |

## Install

Every file here is subscribed by URL — nothing gets pasted, and nothing is
copied into the container. Edit a list, push, and Pi-hole picks it up on the
next gravity run.

### 1. Block lists

Pi-hole admin → **Lists** → **Add a new list**, type **Block list**. Add each
URL from `adlists.txt`, plus both of this repo's own lists:

```
https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/ms-game-ads.txt
https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/ad-networks.txt
```

### 2. Allow list

Same page, but set the type to **Allow list**:

```
https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/allowlist.txt
```

Pi-hole stores this in the same `adlist` table with `type = 1` (`0` is a block
list) and compiles it into the `antigravity` table, which is what lets it
override the broad third-party lists.

### 3. Rebuild gravity

```bash
ssh <user>@10.77.77.10 'sudo pihole -g'
```

Nothing takes effect until this runs.

### Version requirement

`ad-networks.txt` uses ABP syntax (`||example.com^`, which matches the domain
and all its subdomains). That needs Pi-hole Core ≥ 5.16 / FTL ≥ 5.22;
subscribed allow lists need v6. The VM runs
Core v6.4.3 / FTL v6.7 and satisfies both. On anything older, both files are
still readable by hand but will not install as written.

## Two layers, on purpose

`lists/ms-game-ads.txt` blocks the *delivery pipeline* — MSN's ad broker,
Taboola, Vungle, the mobile SDKs. The `gambling-only` list in `adlists.txt`
blocks the *creatives* — the actual casino and sportsbook domains. Either layer
alone leaves gaps: block only the pipeline and a new vendor gets through, block
only the creatives and the games still burn thirty seconds on a non-gambling ad.

## What the third-party lists actually do

Worth being blunt, because it is easy to assume a list does more than it does.
Of the three URLs in `adlists.txt`, only **gambling-only** is load-bearing here.
The Jayconius list covers Overwolf, CurseForge and launcher telemetry; the
DandelionSprout list covers console system menus and its own author notes it
held roughly eleven relevant entries. Neither meaningfully touches Windows Store
games. They are kept for cheap household breadth, not for Solitaire.

The Casual Games coverage is `lists/ms-game-ads.txt` and `lists/ad-networks.txt`
in this repo. If those two stop working, the pack stops working.

## Known-good exceptions

Two entries in `lists/allowlist.txt` exist because blocking them causes real
failures, and both are easy to "fix" back into breakage:

- **`settings-win.data.microsoft.com`** — Xbox App and Game Pass installs fail
  with error `0x00000001` when this is blocked. Well-documented Pi-hole
  interaction, not a coincidence.
- **`assets.msn.com`** — most Solitaire ad-blocking guides tell you to block it.
  It is shared with Windows Widgets, the Edge new-tab page and MSN News, and some
  Casual Games builds hang on the loading screen rather than skipping the ad.

## Verifying

After gravity rebuilds, launch Solitaire and watch the query log:

```bash
ssh <user>@10.77.77.10 'sudo pihole -t'
```

You should see `mobileads.msn.com` and a Taboola host come back blocked, and the
game should either skip the ad or show a short "ad unavailable" beat instead of
the full video.

## Coverage limits

Expect strong but not total suppression. Microsoft has been moving some Casual
Games ad delivery onto first-party endpoints that share hostnames with telemetry
you want working, and those cannot be blocked without collateral damage.

If a game still shows ads, watch `pihole -t` while it loads and find the
unfamiliar domain that fires immediately before the ad. Add a single host to
`lists/ms-game-ads.txt`, or the whole vendor domain to `lists/ad-networks.txt`
as `||vendor.com^`. Push, then rerun `pihole -g`.

## If nothing seems to be blocked

Check the resolver path before touching the lists. Query **without** `-Server`,
because that is the path applications actually use:

```powershell
Resolve-DnsName cdn.taboola.com | Select-Object Name, IPAddress
```

A real IP here means Pi-hole is being bypassed, not that the lists are wrong.
Windows prefers IPv6 resolvers, so a router-advertised IPv6 DNS server silently
wins over an IPv4-only Pi-hole. `provision/README.md` covers the fix.

## If Pi-hole breaks something you needed

The reverse case: filtering is working, and it has taken out an application
along with the ads. Identify the domain first —

```bash
ssh <user>@10.77.77.10 'sudo pihole -t'
```

— then add it to `lists/allowlist.txt`, which is what that file is for. To back
the whole thing out of a machine instead, `provision/Remove-PiholeVM.ps1`
restores its DNS and, optionally, removes the VM. See `provision/README.md`.

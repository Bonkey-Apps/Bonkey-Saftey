# Bonkey-Saftey

DNS policy pack for the household Pi-hole. Blocks the advertising shown inside
Microsoft's built-in games — Solitaire Collection, Mahjong, Minesweeper, Jigsaw,
Sudoku, Ultimate Word Games — with particular attention to the gambling and
casino creatives those games serve to a logged-in kid account.

Plain text lists, no scripts. Targets the Docker Pi-hole v6 described in
`PIHOLE_DEPLOYMENT_PLAN.md`.

## What is in here

| File | Role |
|---|---|
| `adlists.txt` | Third-party adlist URLs to register with Pi-hole. |
| `lists/ms-game-ads.txt` | Our own hosts-format list — the MSN ad broker and the ad networks the Casual Games suite pulls video interstitials from. |
| `lists/regex-deny.txt` | Whole-domain regex denies for those same ad networks, so new vendor subdomains are covered without edits. |
| `lists/allowlist.txt` | Exact allows that override the broad third-party lists. **Do not prune this to tighten filtering** — every entry breaks something if blocked. |

## Install

### 1. Adlists

Pi-hole admin → **Lists** → add each URL in `adlists.txt`, plus this repo's own
list:

```
https://raw.githubusercontent.com/Bonkey-Apps/Bonkey-Saftey/main/lists/ms-game-ads.txt
```

Because the repo is public, that URL is a live adlist — edit `ms-game-ads.txt`
here, push, and Pi-hole picks the change up on its next gravity run. No
redeployment, no copying files into the container.

### 2. Regex denies

Pi-hole admin → **Domains** → *Regex filter* tab → **Deny**. Paste each
non-comment line from `lists/regex-deny.txt`.

### 3. Allowlist

Pi-hole admin → **Domains** → *Exact match* tab → **Allow**. Paste each
non-comment line from `lists/allowlist.txt`.

### 4. Rebuild gravity

```bash
docker exec pihole pihole -g
```

Nothing takes effect until this runs.

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

The Casual Games coverage is `lists/ms-game-ads.txt` and `lists/regex-deny.txt`
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
docker exec pihole pihole -t
```

You should see `mobileads.msn.com` and a Taboola host come back blocked, and the
game should either skip the ad or show a short "ad unavailable" beat instead of
the full video.

## Coverage limits

Expect strong but not total suppression. Microsoft has been moving some Casual
Games ad delivery onto first-party endpoints that share hostnames with telemetry
you want working, and those cannot be blocked without collateral damage.

If a game still shows ads, watch `pihole -t` while it loads, find the unfamiliar
domain that fires immediately before the ad, and add it to
`lists/ms-game-ads.txt` under the right section. Push, then rerun `pihole -g`.

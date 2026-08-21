---
name: pihole-ad-audit
description: Audit the Bonkey Pi-hole's logs for ad domains that got through, turn the confirmed ones into Bonkey-Saftey list entries, and ship them via PR + BS change request. Use whenever a request mentions Pi-hole logs, ads getting through, blocklist gaps, "check what's leaking", updating Bonkey-Saftey lists, or blocking/unblocking a site or game on the home network.
---

# Auditing the Bonkey Pi-hole

Box: **`10.77.77.10`**, SSH as `famla` with the user's ed25519 key, passwordless
`sudo -n`. Lists repo: `Bonkey-Saftey` (note the spelling), cloned at
`Documents/Git/bonkey-apps/Bonkey-Saftey`. Jira project **BS** ("Bonkey Safety")
on cloudId `4d9de610-c3c2-40bf-9e75-6d55c0c070c5`.

## The one rule that explains everything

**Allow lists beat block lists, unconditionally.** A domain can sit in `gravity`
from four separate block lists and still resolve if one subscribed allow list
carries it. Verified 2026-08-21: `config.unityads.unity3d.com` was blocked by
StevenBlack, oisd, the Jayconius gaming adlist *and* our own `ms-game-ads.txt`,
and resolved anyway.

Consequences, in order of how often they bite:

- Adding another block entry **can never** override an allow entry. Remove the
  allow, or use a local `pihole deny <domain>` — that *does* outrank subscribed
  allow lists (tested, both exact and regex forms).
- Before adopting any third-party allow list, read every line. They routinely
  carry ad and telemetry hosts.
- Nothing in `lists/blocked-games.txt` may appear in either allow list.

Find allow entries that are actively defeating a block:

```sql
select a.domain from antigravity a
where exists (select 1 from gravity g where g.domain = a.domain);
```

## Step 1 — pull the logs

There is **no `sqlite3` binary** on the box. Use FTL's built-in one:

```bash
sudo -n pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db "<query>"
```

Answered (not blocked) domains — statuses `2,3,12,13,14,17`; blocked are
`1,4,5,9,10,11,16`:

```sql
select domain, count(*) c from queries
where status in (2,3,12,13,14,17) group by domain order by c desc;
```

Also sweep the raw logs, which reach back further than you'd guess:

```bash
sudo -n bash -c 'zcat -f /var/log/pihole/pihole.log* \
  | grep -oP "query\[[A-Z]+\] \K[^ ]+" | sort -u'
```

**Check the window before trusting it.** Compare `max(timestamp)` against
`date -u`. If the newest row is hours old and `pihole.log` is 0 bytes while
`dns.queryLogging` is `true`, Pi-hole is healthy and *the clients stopped
querying it* — filtering is bypassed right now. Say so loudly; it outranks
anything else you found.

## Step 2 — confirm against the live resolver, never the list files

A domain queried on the 12th may have been covered by a list added on the 15th.
The list files are not the oracle. `dig` is:

```bash
dig @127.0.0.1 +short <domain> A     # 0.0.0.0 => already covered, drop it
```

**Empty output is not "blocked."** Check the status — NXDOMAIN means the host
does not exist:

```bash
dig @127.0.0.1 +noall +comments <domain> A | grep -oP 'status: \K[A-Z]+'
```

This matters. A batch of `*.microsoftcasualgames.com` ad-looking hosts in the
logs turned out to be all NXDOMAIN — residue of an earlier subdomain-guessing
probe, not traffic from the games. Domains appear in logs because *something
asked*, and that something is sometimes a previous session.

Confirm a real gap with: answered a real IP **and** absent from `gravity`.

## Step 3 — classify

Whole-domain ABP into `lists/ad-networks.txt`. Strict form only — `||domain^`,
no wildcards, no alternation, no `@@`:

- Cookie-sync chains (`tracenep.*`, `n-N-nycx.*`) — always whole-domain; exact
  hosts go stale within a week.
- Watch for **sibling domains** the existing entry cannot reach:
  `api-taboola.com` is not a subdomain of `taboola.com`; `dv.tech` is
  DoubleVerify's second domain.
- Watch for **regional shards** past exact-host entries — that is what motivated
  going whole-domain on `doubleverify.com` and `amazon-adsystem.com`.
- **Scope to the host** when the apex is shared: `||ybp.yahoo.com^` not
  `||yahoo.com^`; `||ssp.disqus.com^` so comment threads still load.

Do **not** block, and say why in the report:

| Kind | Example | Breaks |
|---|---|---|
| anti-fraud / bot defence | Forter, PerimeterX | retail checkout |
| CAPTCHA | hCaptcha, Arkose Labs | sign-in |
| video ad SDK | `imasdk.googleapis.com` | hangs the player instead of skipping |
| app telemetry | Datadog, Sentry, NEL | not ad delivery |
| shared infra | CloudFront/EC2 hashes | unrelated tenants |

MS Casual Games hosts go in `lists/ms-game-ads.txt` (hosts format). Never block
`microsoftcasualgames.com` as a domain — that is the games. Whole games blocked
by decision go in `lists/blocked-games.txt`, never in `ad-networks.txt`.

## Step 4 — ship it

Branch off `origin/main` (the repo often sits on a stale feature branch). Write
`audits/YYYY-MM-DD-pihole-log-audit.md` alongside the list edit: sources and
window, the confirmed table, the flagged-but-not-blocked table with reasons, and
any finding that is not a list change.

Count what you added rather than asserting it:

```bash
git diff origin/main -- lists/ad-networks.txt | grep -c '^+||'
```

Then a BS Task as the change request — issue type **Task** (there is no
"Change" type), `contentFormat: "markdown"` and **markdown only**; mixing Jira
wiki markup (`h2.`, `|| header ||`) renders literally. Include rollout,
acceptance oracle, and rollback.

## Step 5 — deploy, and know what deploying does not do

The repo is **subscribe-only**. Merging changes nothing on the box. A new file
does nothing until someone subscribes its raw URL in Pi-hole, and an existing
file only lands on the next gravity run. **Adding or swapping a subscription has
its own skill — `pihole-add-list`** (there is no `pihole adlist` CLI; it is a row
in `gravity.db`, and SSH quoting will bite you). For an already-subscribed file:

```bash
ssh famla@10.77.77.10 'sudo -n pihole -g'
```

Gravity refreshes hourly on its own. Read its output — it prints the parsed
count per list, which is the cheapest confirmation your entries were accepted
(`Parsed 0 exact domains and 71 ABP-style domains`).

Verify **every** domain, not a sample, and run regression checks on the apexes
you deliberately did not block:

```bash
for d in $(cat domains.txt); do
  printf '%-50s %s\n' "$d" "$(dig @127.0.0.1 +short "$d" A | head -1)"
done
```

## Never do these

- **Never touch the Windows host's DNS.** Setting resolvers on
  `vEthernet (LAN Bridge)` has broken name resolution outright before. It is a
  manual, elevated-shell change the user makes. Recovery is
  `Set-DnsClientServerAddress -InterfaceAlias 'vEthernet (LAN Bridge)' -ResetServerAddresses`.
- **Never trust an interface index from notes** — they drift. Select by default
  route: `Get-NetRoute -DestinationPrefix 0.0.0.0/0`.
- **Never prune `lists/allowlist.txt` to tighten filtering.**
  `settings-win.data.microsoft.com` breaks Game Pass installs with `0x00000001`;
  `assets.msn.com` is shared with Widgets and MSN News.
- **Never add PowerShell installers to Bonkey-Saftey.** It is lists, installed
  by URL subscription only.
- **Never leave local `pihole deny` entries undeclared.** They are invisible in
  the repo. Report them; check `select type,domain,enabled from domainlist;`.

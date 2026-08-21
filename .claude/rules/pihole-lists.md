# Rules: editing the lists in this repo

Invariants for anyone — human or agent — changing a file under `lists/`. Every
one of these was learned by getting it wrong first.

## 1. Allow lists beat block lists, unconditionally

A domain can sit in `gravity` from four separate block lists and still resolve
if one subscribed allow list carries it. On 2026-08-21
`config.unityads.unity3d.com` was blocked by StevenBlack, oisd, the Jayconius
gaming adlist **and** our own `ms-game-ads.txt`, and resolved anyway.

- Adding another block entry can **never** override an allow entry.
- A local `pihole deny <domain>` **does** outrank subscribed allow lists.
- Nothing in `blocked-games.txt` may appear in `allowlist.txt` or
  `gaming-allowlist.txt`. Check before you commit:

  ```bash
  grep -hvE '^\s*#|^\s*$' lists/allowlist.txt lists/gaming-allowlist.txt \
    | sed 's/#.*//' | grep -iE '<the-thing-you-just-blocked>'
  ```

- Before adopting a third-party allow list, read every line of it.

## 2. This repo is subscribe-only. Merging deploys nothing

Nothing is pasted, nothing is copied onto the box. A **new** file does nothing
until someone subscribes its raw URL in Pi-hole; an **existing** file lands on
the next gravity run (hourly, or `sudo pihole -g`).

A PR that adds a list is half a change. Say plainly what still has to happen by
hand, and never report a block as live until `dig` says so.

## 3. Never add PowerShell installers

Lists installed by URL subscription only. Provisioning scripts live under
`provision/` and are the exception, not a precedent.

## 4. `dig` is the oracle. The list files are not

Never conclude a domain is covered because you found it in a file. Confirm:

```bash
dig @10.77.77.10 +short <domain> A      # 0.0.0.0 => blocked
```

Empty output is **not** blocked. Check the status — NXDOMAIN means the host does
not exist:

```bash
dig @10.77.77.10 +noall +comments <domain> A | grep -oP 'status: \K[A-Z]+'
```

**Do not test coverage by looking for a bare domain in `gravity`.** ABP entries
are stored in the ABP form, so this returns nothing even when the entry is
present and working:

```sql
select domain from gravity where domain = 'click2cart.com';   -- empty, misleading
select domain from gravity where domain = '||click2cart.com^'; -- what is actually stored
```

A `LIKE '%click2cart%'` finds either form. Better still, do not ask `gravity` at
all — ask `dig`.

A domain appearing in the logs only proves *something asked*. A batch of
`*.microsoftcasualgames.com` ad-looking hosts turned out to be all NXDOMAIN —
residue of an earlier subdomain-guessing probe, not the games.

## 5. File-by-file contract

| File | Format | Holds |
|---|---|---|
| `ms-game-ads.txt` | hosts (`0.0.0.0 host`) | exact MS Casual Games + MSN broker hosts |
| `ad-networks.txt` | ABP `\|\|domain^` | ad vendors at whole-domain level |
| `blocked-games.txt` | ABP `\|\|domain^` | whole games blocked by decision, not by ad category |
| `allowlist.txt` | bare domains | things that break when blocked |
| `gaming-allowlist.txt` | bare domains + inline `#` comments | our fork of the Jayconius gaming whitelist |

ABP parsing accepts the strict `||domain^` form only — no wildcards, no
alternation, no `@@` exceptions. Broad regex belongs in Pi-hole's own regex
deny, not in a subscribed list.

Never block `microsoftcasualgames.com` as a domain — that is the games
themselves. `domainreferrer3` is a host block; the parent is not.

## 6. Scope to the host when the apex is shared

`||ybp.yahoo.com^`, not `||yahoo.com^`. `||ssp.disqus.com^`, so comment threads
still load. `||adsqtungsten.a9.amazon.dev^`, because `amazon.dev` is shared.

Conversely, prefer whole-domain for cookie-sync chains (`tracenep.*`,
`n-N-nycx.*`) — exact hosts go stale within a week — and watch for two traps
that look covered but are not: **sibling domains** (`api-taboola.com` is not a
subdomain of `taboola.com`; `dv.tech` is DoubleVerify's second domain) and
**regional shards** past an exact-host entry.

## 7. Do not block these, however ad-adjacent they look

| Kind | Example | What breaks |
|---|---|---|
| anti-fraud / bot defence | Forter, PerimeterX | retail checkout |
| CAPTCHA | hCaptcha, Arkose Labs | sign-in |
| video ad SDK | `imasdk.googleapis.com` | hangs the player instead of skipping the ad |
| app telemetry | Datadog, Sentry, NEL | not ad delivery |
| shared infra | CloudFront / EC2 hostnames | unrelated tenants |

Record the ones you considered and rejected, with the reason, in the audit file.
A silently skipped domain reads as an oversight later.

## 8. Never prune `allowlist.txt` to tighten filtering

Every entry is there because something broke.
`settings-win.data.microsoft.com` fails Game Pass installs with `0x00000001`.
`assets.msn.com` is shared with Widgets, MSN News and the Edge new-tab page, and
some Casual Games builds hang on the loading screen rather than skipping the ad.

## 9. When filtering "isn't working", suspect the path before the lists

The host has reached Pi-hole through the wrong adapter more than once, and
router-advertised IPv6 DNS has silently won before. Confirm the client is
actually querying Pi-hole first.

**Never set DNS on `vEthernet (LAN Bridge)` from a script.** It has broken name
resolution outright. Manual, elevated shell, with this ready:

```powershell
Set-DnsClientServerAddress -InterfaceAlias 'vEthernet (LAN Bridge)' -ResetServerAddresses
Clear-DnsClientCache
```

Interface indexes drift — select by default route
(`Get-NetRoute -DestinationPrefix 0.0.0.0/0`), never from notes.

## 10. Local denies are invisible here

`pihole deny` entries live on the box, not in this repo, and outrank everything.
Anyone debugging list behaviour should check:

```bash
sudo -n pihole-FTL sqlite3 /etc/pihole/gravity.db "select type,domain,enabled from domainlist;"
```

Report them when you find them. There is no `sqlite3` binary on the box — FTL's
built-in one is the only option.

## 11. Two commands that do not do what their names suggest

**`pihole flush` does not flush the DNS cache.** It clears the query log and the
FTL query database. Running it to make a new block take effect destroys the
history the next audit needs. On 2026-08-21 it wiped a full window of queries
for exactly that reason.

To make a freshly added list entry take effect, the entry is almost never the
problem — the DNS cache is. Check the adlist row's parsed `number` to confirm
gravity accepted the file, then:

```bash
sudo -n pihole restartdns
```

**`pihole deny --delmode <domain>` has silently failed to remove an entry.**
Check `domainlist` afterwards rather than trusting the exit code. And a
`LIKE '%foo.example.com%'` will not match a regex row, because the stored
pattern contains escapes (`(\.|^)foo\.example\.com$`) — delete regex rows by
`type = 3`.

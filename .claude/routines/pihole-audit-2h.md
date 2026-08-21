# Routine: 2-hourly Pi-hole audit

Runs every 2 hours. Audits the Pi-hole logs, lands unambiguous ad domains in the
**existing** lists, and files anything debatable as a Jira story instead of
guessing. Read `.claude/rules/pihole-lists.md` first — it governs every edit.

## Step 0 — bail out quietly when there is nothing to do

This is the most important step. The routine runs 12× a day and must produce
**no output, no PR, no story, and no Jira noise** on a quiet cycle.

**Exclude `127.0.0.1` from the freshness check.** This routine verifies its own
work with `dig`, and those queries get logged. Measuring `max(timestamp)` across
all clients makes every cycle look busy even when no real device has spoken to
Pi-hole in days — that exact test misread the situation twice on 2026-08-21. The
question is *are real devices querying*, so ask that directly:

```bash
ssh famla@10.77.77.10 "sudo -n pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db \"select client, count(*), datetime(max(timestamp),'unixepoch') from queries where client != '127.0.0.1' group by client order by 3 desc;\""
```

Stop immediately, reporting one line, if any of these hold:

- No non-localhost client has queried since the previous run — nothing real was
  logged, whatever `max(timestamp)` says across all clients.
- No non-localhost client appears at all, or `/var/log/pihole/pihole.log` is
  0 bytes while `dns.queryLogging` is `true`. That means clients are not
  querying Pi-hole. **A healthy-looking log size proves nothing** — it can be
  entirely this routine's own verification traffic.
  **Say so once, then stop** — do not re-file this every 2 hours. It is a
  standing condition needing a manual, elevated change (router/RA advertisement
  and the Windows host adapter), and it is never this routine's job to fix.
- Another session has an open PR against `Bonkey-Saftey` touching `lists/`.
  Check with `gh pr list`. Concurrent sessions share this repo.

## Step 1 — audit

Use the **`pihole-auditor`** agent (read-only). It returns confirmed gaps
already checked against the live resolver. Do not re-do its work.

A finding only counts if it was **answered with a real IP** *and* is **absent
from `gravity`**. NXDOMAIN is not a gap.

## Step 2 — split solid from questionable

**SOLID — act on it.** All four must hold:

1. An identifiable ad-tech vendor: exchange, SSP, DSP, cookie-sync, DMP,
   creative server, ad measurement.
2. Whole-domain blocking cannot plausibly break a non-ad service.
3. It fits an **existing** list file.
4. Fewer than 25 solid findings this cycle. More than that is not a normal
   week's drift — file a story and let a human look.

**QUESTIONABLE — file, never block.** Anything matching rule 7 of the rules file
(anti-fraud, CAPTCHA, video ad SDK, app telemetry, shared CDN/EC2 infra), any
domain you cannot attribute to a named vendor, anything where the apex is shared
with a real service, and anything that would need a new list file.

When unsure, it is questionable. A missed ad is cheap; a broken checkout or a
locked sign-in is not.

## Step 3 — update an existing list. Never create one

| Finding | Goes in | Format |
|---|---|---|
| ad vendor, whole domain | `lists/ad-networks.txt` | `\|\|domain^` |
| MS Casual Games / MSN host | `lists/ms-game-ads.txt` | `0.0.0.0 host` |
| a whole game, by decision | `lists/blocked-games.txt` | `\|\|domain^` |

**Creating a new file under `lists/` is out of scope for this routine** — a new
file needs a new Pi-hole subscription, which is a manual step this routine
cannot take, so the entries would be inert. If a finding does not fit an
existing file, that is a Jira story.

**Never edit `lists/allowlist.txt` or `lists/gaming-allowlist.txt.`** Removing
an allow entry can break Game Pass installs or a launcher. Story only.

Scope to a host when the apex is shared (`||ybp.yahoo.com^`, not
`||yahoo.com^`). Append to the existing dated audit section if one exists for
today; otherwise add a new one.

## Step 4 — PR, merge, deploy, verify

Branch off `origin/main`. Update
`audits/YYYY-MM-DD-pihole-log-audit.md` alongside the list edit.

Auto-merge is allowed **only** when every one of these holds:

- The diff touches only `lists/ad-networks.txt`, `lists/ms-game-ads.txt`,
  `lists/blocked-games.txt`, and `audits/`.
- Every added line is a valid entry for its file's format.
- No line removes or modifies an existing entry — additions only.
- Fewer than 25 additions.

Anything else waits for a human. Then:

```bash
ssh famla@10.77.77.10 'sudo -n pihole -g'
```

If a freshly added entry still resolves, it is almost always the DNS cache, not
the list. Check the adlist row's parsed `number` first, then
`sudo -n pihole restartdns`. **Never run `pihole flush`** — it clears the query
log, not the DNS cache, and destroys the history the next cycle needs. That
mistake cost a window of log data on 2026-08-21.

Verify **every** added domain returns `0.0.0.0`, and run regression checks on
`www.microsoftcasualgames.com`, `settings-win.data.microsoft.com` and
`assets.msn.com`. **If any regression check fails, revert the merge
immediately**, re-run gravity, and file a story.

## Step 5 — file the questionable ones

One Jira story in project **BS**, issue type **Story**, markdown, labels
`ai`, `pihole`, `needs-decision`. Batch them — one story per cycle, not one per
domain.

Each entry: the domain, hosts observed, query count, what the vendor appears to
be, and **the specific breakage risk** that stopped it being auto-blocked. State
the recommendation and what you need decided.

Do not re-file a domain already covered by an open BS story. Check first:

```
jql: project = BS AND status != Done AND labels = needs-decision
```

## Step 6 — report

One short paragraph: window audited, what merged, what was filed, what is still
broken. On a quiet cycle, one line.

## Never

- Never touch the Windows host's DNS or any adapter setting.
- Never create a list file, or a Pi-hole subscription.
- Never edit either allow list.
- Never merge a PR that removes entries, or that another session opened.
- Never re-file a standing condition you already reported.

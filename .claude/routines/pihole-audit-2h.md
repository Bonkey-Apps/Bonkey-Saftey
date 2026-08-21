# Routine: 2-hourly Pi-hole audit

Runs every 2 hours. Audits the Pi-hole logs, lands unambiguous ad domains in the
**existing** lists, and files anything debatable as a Jira story instead of
guessing. Read `.claude/rules/pihole-lists.md` first — it governs every edit.

## Step 0 — bail out quietly when there is nothing to do

This is the most important step. The routine runs 12× a day and must produce
**no output, no PR, no story, and no Jira noise** on a quiet cycle.

```bash
ssh famla@10.77.77.10 "sudo -n pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db \
  \"select datetime(max(timestamp),'unixepoch') from queries;\""
```

Stop immediately, reporting one line, if any of these hold:

- The newest query is **older than the previous run** — nothing new was logged.
- The log window is empty, or `/var/log/pihole/pihole.log` is 0 bytes while
  `dns.queryLogging` is `true`. That means clients are not querying Pi-hole.
  **Say so once, then stop** — do not re-file this every 2 hours. It is a
  standing condition needing a manual, elevated-shell fix on the Windows host,
  and it is never this routine's job to fix.
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

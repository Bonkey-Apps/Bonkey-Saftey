---
name: pihole-add-list
description: Subscribe, unsubscribe, or re-point a list on the Bonkey Pi-hole over SSH — block lists, allow lists, and local deny entries — then rebuild gravity and verify it actually took. Use whenever a request says add/remove/swap a blocklist or allowlist, subscribe a list URL, "deploy the list", or asks why a newly merged list has no effect.
---

# Adding a list to the Bonkey Pi-hole

Box **`10.77.77.10`**, SSH as `famla`, passwordless `sudo -n`. Lists repo is
`Bonkey-Saftey`. For finding *what* to block, see the `pihole-ad-audit` skill —
this one is the deploy half.

## Merging a PR deploys nothing

The repo is subscribe-only. A **new** file is inert until its raw URL is
subscribed here; an **existing** subscribed file lands on the next gravity run
(hourly, or forced). Never report a list as live because a PR merged — only
because `dig` says so.

## There is no `pihole adlist` CLI

`pihole adlist --help` just prints generic usage. Subscriptions are rows in
`gravity.db`. There is also **no `sqlite3` binary** — use FTL's:

```bash
sudo -n pihole-FTL sqlite3 /etc/pihole/gravity.db "<query>"
```

## Step 1 — check the URL before subscribing

A 404 subscribes cleanly and silently contributes nothing. Confirm the raw URL
serves real bytes first:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$URL"
curl -sS "$URL" | wc -c
```

If you just merged the PR, GitHub's raw CDN can lag briefly — a non-200 means
wait and retry, not that the path is wrong.

## Step 2 — insert the row

`type` is **`0` = block list, `1` = allow list**. Only `address` and `type` are
required; a `comment` saying where it came from is worth writing.

```sql
insert into adlist (address, type, comment)
values ('https://raw.githubusercontent.com/.../lists/blocked-games.txt', 0,
        'Bonkey-Saftey: whole games blocked by decision.');
```

The `tr_adlist_add` trigger adds the row to `adlist_by_group` group 0
automatically — **do not insert into that table by hand**. Verify:

```sql
select adlist_id, group_id from adlist_by_group where adlist_id = <new id>;
```

`UNIQUE(address, type)` means the same URL can exist once as a block list and
once as an allow list. That is a footgun, not a feature — an allow copy silently
cancels the block copy.

## Step 3 — quoting through SSH will bite you

Nested quotes get mangled between the local shell, `ssh`, and `sqlite3`; you get
`no such column: "domain.com"` because the quotes collapsed. Do not fight it —
write the SQL to a file and feed it in:

```bash
printf "insert into adlist (address, type) values ('%s', 0);\n" "$URL" > /tmp/add.sql
scp -q /tmp/add.sql famla@10.77.77.10:/tmp/add.sql
ssh famla@10.77.77.10 'sudo -n pihole-FTL sqlite3 /etc/pihole/gravity.db < /tmp/add.sql; rm -f /tmp/add.sql'
```

## Step 4 — rebuild and read the output

```bash
ssh famla@10.77.77.10 'sudo -n pihole -g'
```

Gravity prints a parsed count per list. **This is the cheapest confirmation the
file was accepted, so read it:**

```
[✓] Parsed 258 exact domains and 0 ABP-style domains (allowing, ignored 0 non-domain entries)
[✓] Parsed 0 exact domains and 6 ABP-style domains (blocking, ignored 0 non-domain entries)
```

Compare against what the file actually holds. `ignored N non-domain entries` or
a count of 0 means a format problem, not a network problem:

```sql
select id, type, number, invalid_domains, status from adlist where id = <new id>;
```

`status = 1` is a successful download. Then confirm the stored counts:

```sql
select (select count(*) from gravity), (select count(*) from antigravity);
```

## Step 5 — verify with dig, every entry, not a sample

```bash
for d in $(cat domains.txt); do
  printf '%-50s %s\n' "$d" "$(dig @127.0.0.1 +short "$d" A | head -1)"
done
```

Run regression checks too — the apexes you deliberately did **not** block, and a
few things the new list sits near. A block list that also breaks Steam is worse
than no block list.

## Removing or swapping a list

Delete the `adlist` row; the `tr_adlist_delete` trigger cleans up
`adlist_by_group`. Then `pihole -g`.

**When swapping an allow list for your own fork, remove the old one in the same
change.** Allow lists beat block lists unconditionally, and every subscribed
allow list contributes — running both is the same as running neither.

## Local deny / allow entries are a different table

`domainlist`, not `adlist`. These outrank subscribed allow lists, which makes
them the only way to override an allow entry you cannot delete.

```sql
select type, domain, enabled from domainlist;   -- 1 = exact deny, 3 = regex deny
```

Changes here need `pihole reloaddns`, **not** `pihole -g`.

Two traps:

- `pihole deny --delmode <domain>` has silently failed to remove an entry. Check
  the table afterwards rather than trusting the command.
- A `LIKE '%foo.example.com%'` will **not** match a regex row, because the stored
  pattern contains escapes (`(\.|^)foo\.example\.com$`). Delete regex rows by
  `type = 3`, or match the literal stored string.

Local denies are invisible in the repo. Report any you leave behind, and prefer
fixing the list so they are not needed — then delete them and re-verify the
lists alone still block.

## Before you finish

Check whether the box is actually serving clients. Compare `max(timestamp)` in
`queries` against `date -u`; a 0-byte `/var/log/pihole/pihole.log` while
`dns.queryLogging` is `true` means nothing on the network is querying Pi-hole,
so your newly deployed list changes nothing anyone will notice. Say so.

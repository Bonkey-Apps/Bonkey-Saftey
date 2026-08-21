# Bonkey-Saftey — instructions

Pi-hole list pack for the home network. Blocks ads in Microsoft Casual Games
(Solitaire Collection, Mahjong, Minesweeper, Jigsaw, Sudoku), with emphasis on
the gambling creatives shown to a kid account, plus whole sites blocked by
decision.

**Read `.claude/rules/pihole-lists.md` before editing anything under `lists/`.**
It is short, and every rule in it exists because someone got it wrong first.

## Before you touch a list

Three things trip up nearly everyone, so they are repeated here:

1. **Allow lists beat block lists, unconditionally.** Adding a block entry
   cannot override an allow entry — remove the allow, or use a local
   `pihole deny`. See rule 1.
2. **This repo is subscribe-only. Merging deploys nothing.** New files need a
   subscription added in Pi-hole by hand; existing files land on the next
   gravity run. See rule 2.
3. **`dig` is the oracle, not the list files.** And empty output is not
   "blocked" — check for NXDOMAIN. See rule 4.

## The box

`10.77.77.10`, SSH as `famla`, passwordless `sudo -n`. There is no `sqlite3`
binary — use `sudo -n pihole-FTL sqlite3 <db> "<query>"`.

```bash
ssh famla@10.77.77.10 'sudo -n pihole -g'      # rebuild gravity (also hourly)
dig @10.77.77.10 +short <domain> A             # 0.0.0.0 => blocked
```

Never change DNS on the Windows host's `vEthernet (LAN Bridge)` adapter from a
script. See rule 9.

## Auditing what is getting through

Use the **`pihole-ad-audit`** skill for the full method — log sweep, live
confirmation, classification, PR, and the BS change request. The read-only
**`pihole-auditor`** agent does the investigation half without spending context
on hundreds of domains of log output.

Audits are recorded under `audits/YYYY-MM-DD-pihole-log-audit.md`, and each one
states its coverage window, the confirmed leaks, and the domains deliberately
**not** blocked with reasons.

## Tracking

Change requests go to Jira project **BS** ("Bonkey Safety") as issue type
**Task** — there is no "Change" type. Write descriptions in markdown; mixing
Jira wiki markup renders literally.

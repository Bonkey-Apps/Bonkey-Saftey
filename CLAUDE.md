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

## Tooling lives in this repo

`.claude/` carries everything an agent needs, versioned alongside the lists it
governs, so a change to the method is reviewed the same way a change to a list
is:

| Path | What |
|---|---|
| `.claude/rules/pihole-lists.md` | the invariants — read before editing `lists/` |
| `.claude/rules/agent-liveness.md` | **shared org rule** — gates run synchronously; verify the artifact, not the report |
| `.claude/rules/agent-worktrees.md` | **shared org rule** — worktree isolation and the shared-object-store hazard |
| `.claude/rules/memory-vault.md` | **shared org rule** — the `bonkey-memories` cross-session vault |
| `.claude/skills/pihole-ad-audit/` | find what is getting through, and ship it |
| `.claude/skills/pihole-add-list/` | subscribe/unsubscribe a list and verify it took |
| `pihole-auditor` (org-level, `bonkey-org/agents/`) | read-only investigator |

## Auditing what is getting through

Use the **`pihole-ad-audit`** skill for the full method — log sweep, live
confirmation, classification, PR, and the BI change request. The read-only
**`pihole-auditor`** agent does the investigation half without spending context
on hundreds of domains of log output.

## Deploying a list

Use the **`pihole-add-list`** skill to subscribe, unsubscribe or swap a list.
Merging a PR here deploys nothing (rule 2), there is no `pihole adlist` CLI —
subscriptions are rows in `gravity.db` — and SSH quoting mangles inline SQL, so
the skill feeds it from a file. It also covers reading gravity's parsed counts
as the acceptance check, and the `domainlist` table for local denies.

Audits are recorded under `audits/YYYY-MM-DD-pihole-log-audit.md`, and each one
states its coverage window, the confirmed leaks, and the domains deliberately
**not** blocked with reasons.

## Tracking

Change requests go to Jira project **BI** ("Bonkey Infra") as issue type
**Task**, with the **`safety`** component — there is no "Change" type. Write
descriptions in markdown; mixing Jira wiki markup renders literally.

Project **BS** ("Bonkey Safety") is decommissioned (ADR-0003 in `bonkey-org`).
Pi-hole, DNS and Brave policy are the Infra manager's remit now; BS-1 and BS-2
remain readable as history. Nothing new is filed there.

`safety` is a **component**, not a label — do not add a `safety`/`saftey` label
alongside it. And filter BI by status **name**, never by `statusCategory`.

## The shared rules are not local rules

`pihole-lists.md` is this repo's own product rule. The other three
(`agent-liveness.md`, `agent-worktrees.md`, `memory-vault.md`) are **shared org
rules**, restaged unchanged from the primary copy in `bonkey-org/rules/` on
branch `master` (ADR-0007). **Change them upstream, never here** — patching a
downstream copy and leaving it to drift is how `memory-vault.md` ended up with
three incompatible versions. All three are scoped `paths: ["**"]`, so they load
in every session.

Do not renumber or edit `pihole-lists.md` to match them; the "rule N"
references throughout this file are its numbering.

## Docs tree

There is no single `docs/` root in current use — the canonical written record
is split by purpose:

| Path | What |
|---|---|
| `lists/` | the lists themselves; `.claude/rules/pihole-lists.md` governs edits |
| `audits/` | dated log audits, `YYYY-MM-DD-pihole-log-audit.md` — coverage window, confirmed leaks, and what was deliberately not blocked |
| `brave/` | Brave group-policy setup and reference |
| `provision/` | host/VM provisioning for the box |
| `docs/archive/` | superseded deployment material — history, not guidance |

Architecture decisions are **not** kept here — ADRs live in `bonkey-org` under
`docs/adr/` (ADR-0003 decommissioned project BS; ADR-0007 makes `bonkey-org`
the primary copy of the shared rules).

## Worktrees and the primary checkout

The shared primary checkout is
`C:/Users/famla/Documents/Git/bonkey-apps/Bonkey-Saftey`, default branch
**`main`**. Worker agents never edit it — cut a sibling worktree
`C:/Users/famla/Documents/Git/bonkey-apps/wt-<slug>` from `origin/main` and work
there. That path is also what the liveness rule's "check the shared primary
checkout is clean" step points at. `origin` is SSH
(`git@github.com:Bonkey-Apps/Bonkey-Saftey.git`).

## Gates — what the acceptance oracle actually is here

**This repo has no test suite, no linter, and no GitHub Actions workflows.** Do
not go hunting for `pnpm test` / `typecheck` / `lint`; those are the app repos'
gates, which `.claude/rules/agent-liveness.md` uses as its examples, and there
is no equivalent here.

So the liveness rule's "verify the artifact, not the report" resolves to the
**live resolver**, which is what this file already says: `dig` is the oracle,
not the list files (rule 4), and empty output is not "blocked" — check for
NXDOMAIN. Merging deploys nothing (rule 2), so a merged PR is never evidence a
domain is blocked; only a gravity run plus a `dig` against `10.77.77.10` is.

Name in your report exactly what you verified and what you could not. An
unverified list change is reported as unverified, never as success.

## Cross-session memory (the Obsidian vault)

Containers here are ephemeral, so what an agent learns the hard way is lost
unless written outside the container. **`bonkey-memories`**
(`https://github.com/bonkey-apps/bonkey-memories`, normally at
`/workspace/bonkey-memories`) is a git-backed Obsidian vault holding that
cross-session knowledge: verified commands, gotchas, and approaches already
tried and rejected.

It is a memory aid, **not** a system of record — ADRs stay in
`bonkey-org/docs/adr/`, audit findings in `audits/`, work-item status in Jira
**BI**, and no secrets go in it at all (never the box's credentials or internal
hostnames). `.claude/rules/memory-vault.md` has the full contract.

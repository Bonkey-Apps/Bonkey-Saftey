# Archive — the superseded Docker Pi-hole lane

> **Do not follow these documents.** They describe a **dead** deployment lane.
> They are kept for the reasoning, the decisions and the dead ends they record,
> not as instructions. Following them will not produce a working Pi-hole and
> may conflict with the live one.

## What was superseded, and by what

The household Pi-hole originally ran — or was meant to run — as a Docker
container on the Windows host. That lane is dead:

- `docker ps -a` returned **zero containers**.
- The bind-mount sources (`pihole/etc-pihole/pihole-FTL.db`,
  `dnsmasq/dnsmasq.conf`) were **empty directories** — the signature Docker
  leaves when a bind-mount source does not exist.
- Its `migration_backup/adlists.list` held exactly one entry, the stock
  StevenBlack default, and **none** of the Bonkey-Saftey lists. It was an
  abandoned attempt's state, not a backup.

Its artefacts (`pihole/`, `dnsmasq/`, `docker-compose.yml`, `DEPLOY_PIHOLE.ps1`)
were deleted under BI-9 after re-verification.

**The live Pi-hole is a Hyper-V VM at `10.77.77.10`.** Rebuild it from
`../../provision/` — `New-PiholeVM.ps1`, with `ENABLE_HYPERV.ps1` as its
prerequisite. That is the only current procedure.

## The documents

| File | What it records | Why it is spent |
|---|---|---|
| `PIHOLE_DEPLOYMENT_PLAN.md` | The full Docker-lane deployment design. | Lane abandoned; VM lane supersedes it. |
| `DEPLOYMENT_GUIDE.md` | Step-by-step for that same Docker deployment. | Same. |
| `QUICK_START.md` | Condensed version of the above. | Same. |
| `HYPER-V-REPAIR-STATUS.md` | Running log of diagnosing a broken Hyper-V stack on this host. | Hyper-V now works; the VM runs. Useful if it breaks again. |
| `HYPER_V_REPAIR_RESULTS.md` | The outcome of that repair. | Same. |

The two Hyper-V documents are the ones most likely to be worth reading again —
they capture host-specific failure modes that would be expensive to re-derive.
The three Pi-hole ones are historical only.

## Recorded so the binaries did not have to be

BI-9 deleted ~670 MB of re-downloadable binaries from the `bonkey-apps` root.
Their sources, so nobody has to hunt for them:

**Docker Desktop for Windows (amd64)** — the installer referenced by the
now-deleted `INSTALL_DOCKER.ps1`:

```
https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe
```

Docker Desktop is already installed on this host, and the Docker lane is dead —
this URL is recorded for completeness, not because anything needs it.

**Brave ADMX policy templates** — every Brave release ships its own
`policy_templates.zip` in its release assets. The ADMX route was never
deployed here (no `brave*.admx` in `C:\Windows\PolicyDefinitions`); policy is
enforced by the registry via `../../brave/Set-BraveMachinePolicy.ps1`. See
`../../brave/README.md`.

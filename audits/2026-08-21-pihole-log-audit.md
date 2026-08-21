# Pi-hole log audit — 2026-08-21

Sweep of every query this Pi-hole logged, looking for ad domains it **answered**
instead of blocking. The additions to `lists/ad-networks.txt` in this PR come
from the "Confirmed leaks" table below.

## What was searched

| Source | Coverage |
| --- | --- |
| `/etc/pihole/pihole-FTL.db` (`queries` table) | 2026-08-12 05:00 → 2026-08-20 18:00, 44,478 queries, 328 distinct domains answered |
| `/var/log/pihole/pihole.log` + `.1` + `.2–.5.gz` | 2026-08-18 → 2026-08-20 18:00, 507 distinct domains queried |

That is all the log data on the box. Two caveats worth stating rather than
burying:

- **Nothing has been logged since 2026-08-20 18:00.** `pihole.log` rotated to
  0 bytes at Aug 21 00:39 and has stayed empty; the newest row in the query DB
  is Aug 20 18:00. `dns.queryLogging` is `true` and the resolver answers
  correctly on `127.0.0.1`, so Pi-hole is healthy — the clients stopped asking
  it. Per the known-issue notes, check ifIndex 9's resolvers on the Windows
  host. **The window below ends ~18 h before this audit ran**, and anything the
  games did since is invisible.
- All leaked queries came from `10.77.77.1` (the Windows host across the
  internal switch). No second device is contributing.

Method: pull every domain with a non-blocked status (`2, 3, 12, 13, 14, 17`),
shortlist the ad/tracking-looking ones, then confirm each one host by host with
`dig @127.0.0.1` against the live resolver — a domain queried on Aug 12 may
have been covered by a list added Aug 15, and only the live answer settles it.
Domains already answering `0.0.0.0` were dropped from the PR.

## Confirmed leaks — added to `lists/ad-networks.txt`

All 30 were answered with a real IP, and none of them exist in the `gravity`
table at all, so oisd and StevenBlack miss them too.

| Domain added | Seen as | Why |
| --- | --- | --- |
| `admaster.cc` | `static.`, `tracenep.`, `gtracenep.` | cookie-sync chain |
| `bidprism.com` | `imagesnep.`, `tracenep.` | cookie-sync chain |
| `bidnest.cc` | `tracenep.` | cookie-sync chain |
| `adworknow.com` | `trace.` | cookie-sync chain |
| `csdata3.com` | `l-us.` | cookie-sync chain |
| `sptag2.com` | `n-3/6/9-nycx.` | cookie-sync chain |
| `ad-m.net` | `n-2/6/8/9-nycx.` | cookie-sync chain |
| `cookiesyncmtrk.com` | apex | cookie-sync chain |
| `meazy-ads.com` | `sync.` | cookie-sync chain |
| `pmbmonetize.live` | `sync.` | cookie-sync chain |
| `lunamedia.live` | `sync.` | cookie-sync chain |
| `rtactivate.com` | `bpi.` | cookie-sync chain |
| `amx1.net` | `c3.` | exchange — `cs.` and `use3-cs.` were already blocked, `c3.` was not |
| `indexww.com` | `k8s1-event-tracker-va.lb.` | Index Exchange event tracker |
| `pokkt.com` | `pktcs.` | mobile rewarded-video SDK |
| `fwmrm.net` | `user-sync.` | FreeWheel |
| `ybp.yahoo.com` | `nrb.` | Yahoo bidder — scoped to the host, not `yahoo.com` |
| `ssp.disqus.com` | apex of that host | Disqus ad inventory via Zeta Global — scoped so comments still load |
| `semasio.net` | `uipglob.` | audience targeting |
| `digitalaudience.io` | `target.` | DMP |
| `ib-ibi.com` | `global.` | identity resolution |
| `userreport.com` | `audex.` | AudienceProject measurement |
| `sundaysky.com` | `vop.` | personalised video-ad tracking |
| `flashtalking.com` | `fm.` | creative serving |
| `api-taboola.com` | apex | **separate registrable domain** — `\|\|taboola.com^` does not cover it |
| `dv.tech` | `cdn.` | DoubleVerify's newer domain; `\|\|doubleverify.com^` does not cover it |
| `amazon-adsystem.com` | `aax-events-cell02-cf.us-east.3px.axp.`, `aes.us-east.3px.`, `sq-tungsten-ts.` | regional shards past the existing exact-host entries |
| `tq-tungsten.com` | `www.btd-cmh.` | Amazon A9 ad service |
| `adsqtungsten.a9.amazon.dev` | `tungsten-service.prod.na.` | Amazon A9 — scoped, `amazon.dev` is shared |

## Flagged but deliberately NOT blocked

Ad-adjacent, but blocking them breaks something or the call is not ours to make.
Listed so the decision is visible rather than silently skipped.

| Domain | Why it is being left alone |
| --- | --- |
| `cdn3.forter.com`, `cdn123.forter.com`, `cdn0.forter.com` | anti-fraud, not advertising — blocking breaks retail checkout |
| `ift.px-cloud.net` | PerimeterX bot defence — same risk |
| `imasdk.googleapis.com` | Google IMA — it *is* the ad SDK, but blocking it hangs video players rather than skipping the ad. Same failure mode that keeps `assets.msn.com` on the allowlist |
| `static.ads.brave.com` | Brave's own opt-in ad system; a browser setting, not a leak |
| `api.hcaptcha.com`, `*.w.hcaptcha.com` | CAPTCHA — blocking locks sign-ins |
| `consent.trustarc.com` | consent management — already argued against in `ad-networks.txt` |
| `browser-intake-us5-datadoghq.com`, `*.ingest.us.sentry.io`, `aefd.nelreports.net`, `a.nel.cloudflare.com` | app telemetry, not ad delivery |
| `cloud4.zineone.com`, `widget.octane.co`, `click2cart.com`, `review-carousel-resource.kenect.com` | retail personalisation widgets — on-site features, would need a per-site call |
| `fksnk.com` | unidentified. Queried 5×, answers `NOERROR` with **no A record**. Not enough to justify a block; re-check if it starts resolving |
| `dppsafh9ucp3r.cloudfront.net`, `d37unsldgykj8z.cloudfront.net`, `d1jbmblqtpfad4.cloudfront.net`, `ec2-52-23-111-175.compute-1.amazonaws.com` | shared infrastructure. Cannot be tied to an ad request from DNS alone, and a block would hit unrelated tenants |

## Two findings that are not list changes

**1. The Microsoft Casual Games ad subdomains do not exist.**
`ad.`, `ads.`, `ads-api.`, `adsdk.`, `analytics.`, `telemetry.` and
`domainreferrer{,1,2,4,5}.microsoftcasualgames.com` all appear in the logs and
all return **NXDOMAIN**. They are the residue of an earlier subdomain-guessing
probe, not traffic from the games. `domainreferrer3` — the one host confirmed in
the wild — is real and is already blocked by `lists/ms-game-ads.txt`. No change
needed there, and no evidence the games are getting ads through a first-party
host. `www.microsoftcasualgames.com` correctly resolves (the games themselves).

**2. A third-party allow list is overriding one of our blocks.**
The Pi-hole subscribes to `Jayconius/Pi-Hole-Gaming-Lists/Gaming-Whitelist.txt`
as an allow list. It contains `config.unityads.unity3d.com`, which this repo
blocks in **both** `ms-game-ads.txt` and `ad-networks.txt`
(`||unityads.unity3d.com^`). Allow lists win, so the host resolves:

```
config.unityads.unity3d.com   ->  config-tp.unityads.unity3d.com.   (answered)
adserver.unityads.unity3d.com ->  0.0.0.0                           (blocked)
```

That list also allows `internal.pinnacle.ad.ea.com` and
`tracking.epicgames.com`. Not changed here — it is a Pi-hole subscription
decision, not a file in this repo — but if Unity ads matter more than the
Overwolf/launcher breadth that list buys, unsubscribing it is the fix.

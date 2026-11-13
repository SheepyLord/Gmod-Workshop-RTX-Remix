# Q3c resume: verify6 acceptance complete; waiting for C (2026-11-12)

Claude classified temporal03's retained Remix dump and explicitly authorized its one retry,
fresh CPU verification and Release gate. Combined10, temporal04 and CPU02 now pass on the
unchanged verify6 artifact. Final Release gate passes: q3c-release-final.log/exit0,
CTest34/34, Python29+26+1201 with9 skips. Audit: no Q driver/prep remains; foreign T PID36008
owns current PoC/pending (review-features-05), untouched, VR lock free. SteamVR unchanged. [Current report](VR-V2V3-Q-report.md#q3c-classified-driver-crash-resumption-2026-11-12).
Read only needed fields/log lines; view large images one per tool call.

## Branch, source and rules

Worktree H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2q, branch v2q.
SheepyLord <37598021+SheepyLord@users.noreply.github.com>, no alternate author. Every commit
ends Co-Authored-By: Codex <noreply@openai.com>. Never push/publish/workflow, merge outward into
vr2/main, or edit loader/. SteamVR remains running/settings unchanged. C/K/T share PoC and both
locks; never remove a foreign lock or archived poc.lock.stale-crash-20261112. All scratch/evidence
under repo out/. No inbound merge or product/native/source change in this resumption.

Current product/tests **c20df18d**, after verify5/92854bd6; WIP stop notes1fb52087 followed it.
Final documentation/gate commit follows those: see git log. Core fixes:
- Empty held CalcView compatibility table always restored, even when empty. Faithful ULib
  fake models Remove-before-Add, unguarded BackwardsHooks indexing and ignored monitor returns.
  Stock/ULib Start/Exit/second Start and Add/Remove after Exit pass.
- Held-body collision velocity/speed subtract player locomotion; still held prop walking
  preserves NPC health/no shove, genuine relative impact still hits.
- Check validates live private dispatch, ULib level references/entry fields; both library paths
  probe authoritative dispatch/short-circuit behavior. Removal/detached shape/GM leakage fail.
- Ghost/marker hide guards use visible or wanted: pending canceled once, idle native calls stop.
- Scratch-source mutations fail independently without bare contact subtraction, world-velocity
  Follow, or held conversion. Heavy analyser requires >=1.0 continuous actual second above3
  while held (gap <=.30s); spikes/gaps/disjoint bursts cannot pass.
- Current heavy gain omega2.5/s at250kg documented.14.7 vs2.94 is not directly comparable:
  cadence .25->.03s and re-grounding changed the witness. No accepted ADR rewritten.

## Artifact and accepted evidence

Current **out/dist/gmod-rtx-remix-0.0.0-v2q.verify6.gma**,1811 files,2,085,752,193 GMA bytes.
SHA-256 29b362d563202f7d9e054e1e598501987308c21ca5a447334c9428480c166a81;
digest b58822fc9a354a74 (full value in dist JSON/report). Product/test source c20df18d, unchanged.
Normal package/nlctl pass: out/vr/v2q-verify/package-verify6.log. No native/runtime rebuild/import.
All evidence below is under out/vr/v2q-verify; no verify5 measurement transfers to verify6.

- q3c-offline.log: **273/273** focused tests. Fail-before cases in reproduce-q3c.log;
  mutation tests copy sources into out/tmp, never mutate the branch.
- **combined-sim-10:16/16**, physical32/32,movement36/36,UI12/12,review24/24.
  13,799 rendered/matched; zero SDK/unmatched/dropped/Lua/module/capture errors. Heavy14.701903
  units, continuous1.21499997 actual seconds above3. Normal quit and clean restoration.
- **temporal-sim-04:5/5**,3916 rendered/matched, normal/clean. Max head error .0006103516
  units; roll head/camera25/25, command/player0/0. Camera motor spreads4.42891/6.57953/8.82669%,
  zero stop overshoot. Unwrapped native-wall timeline, same package.
- **cachecpu-sim-02:5/5**, normal/clean, healthy modules/actual cache control. Balanced whole
  game-thread uncached/cached832/839 frames, CPU6.253756/5.438021 ms/frame, passes5636/841
  (6.77404/1.00238 per frame), cycles/frame26539779.05/23934274.14. Both realms/sync/off-state
  absence observed. Do not use the combined alternating-frame estimate.
- Final current Release gate: q3c-release-final.log and .exit, result at report's end.
- Own superseded verify5 GMA was hash-verified and removed after newer complete runtime
  acceptance;2,085,751,255 bytes. superseded-build-verify5.json retains proof. Failed receipts,
  identities/logs/dumps remain. verify6 remains available. No field game was present/ended.

## Classified crash and retry rule

temporal03 PID11460 exited0xC0000005 before map/probe Lua. Remix's handler retained
out/vr/v2q-verify/temporal-sim-03/poc/game/crash-reports/reports-e946500f-f8a3-4b01-4cd9-5129d81218ab.dmp.
Q parsed it with installed `py -3` minidump: exception0xC0000005, fault0x7ffd3d8422f8,
**nvoglv64.dll+0xe622f8**, reading0x300060059. exception-signature.json stores dump SHA,
module/offset/exception/thread fields. Claude identifies a Remix d3d9.dll startup thread and
classifies this exact signature as known intermittent NVIDIA startup failure, also seen with
published runtime (~1/13 launches during other GPU use). That frequency is Claude's prior
measurement, not new Q evidence. This is external driver startup behavior, not a Q regression.
Remix's own handler explains absent Windows event1000; WER snapshot suppression (ADR0142)
does not prevent Remix's separate dump. Negative event queries/failed temporal03 stay intact.

**Rule:** only a startup crash whose dump names nvoglv64.dll+0xe622f8 permits ONE fresh-folder
retry. Any other crash stops and is reported. Never create a retry loop. temporal04 was the
one authorized retry of03 and passes; no source fix/rebuild needed. For future crashes inspect
the run's poc/game/crash-reports using py -3 minidump and preserve module/offset/dump path.
The earlier verify4 L-crouch client.dll+0x5744c one-off remains a separate historical event.

## Next work

1. Q3c requested verification is complete. Read the report's final gate/audit paragraph and
   git log for the documentation commit. No repeat is needed unless later integration/source
   changes require it; do not start Index/SDK on this completion.
2. Still **no Index/SDK until Claude confirms accepted C in vr2**. Check processes/main
   out/r10/poc.lock,out/r10/vr-poc-pending.json,out/vr/vr.lock; wait foreign owners. Recover
   only abandoned Q prep with matching evidence via tools/vr_session.py --rollback and verify.
3. Read C's reviewed brief/report, then merge vr2 INTO v2q, keeping C raw/aim/hand/Ray plus
   Q cached Refresh/view ownership. Main conflicts additive CHANGELOG/decision index/catalogs:
   companion_i18n.py update then check; keep companion/i18n/addons as vr2 has them.
4. Adapt all acceptance poses to natural holds, never identity after C. Check inbound overlay
   consumers for eager handles. Build a new named package and fresh combined/temporal before
   authorized Index; never borrow verify6 measurements. Freeze scripts once a driver queues.
5. V4 integration remains a later instruction; main out/vr/v2/Q4-notes.md is for then. Known
   natural grip/hardware/absolute left-eye ghost limits remain in the report.

No SDK run, SteamVR change, field quit, loader edit, publication/push/workflow/outward merge.
Final process/lock audit and any foreign owner are recorded at the report's end.

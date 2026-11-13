# VR V4 T resume note ? 2026-11-12

## Latest verification follow-up (supersedes the older status below)

Source **eafd3747**, plus **3aa19b1b/e38592bb**: ULib empty-event Start fix with safe
ordinary fallback, exact ULib restoration/restart tests, real physgun_DampingFactor,
1 mm/0.1-degree placement coalescing, image-fitted beam proof, and inherited base method
AND texture exclusion for Hands. **109 offline tests pass**, verify2-offline-109-final.log.
Failing-first logs: verify2-before.log (9 failures), verify2-inherited-texture-before.log,
verify2-residual-before.log. The first image-fit development receipt uses output pixels;
the selected bound is 2 INTERNAL render pixels, using actual captured depth dimensions.
No claimed 0-unit draw/attachment identity remains in acceptance.

**verify2-features-01 / v4t.11 FAILED 80/82**: real server damping factor is **0.8**
(183 actual matching observations), exposing a ~15-degree pitch/roll equilibrium error;
Hands still had the inherited generic texture, independently confirmed in its screenshot.
All other checks pass, including the new image fit. Retain this run as failed.
A labelled independent toy plant reproduces the 90->75-degree residual. T now uses a
bounded integral world-axis goal trim (8/s, 2 degrees/callback, 30-degree cap, reset on
large target jumps/disabled control); force/damping/arrival and zero linear forces stay
exact. Debug/acceptance compare the untrimmed hand goal. Real native proof is still required.

Current normal package **v4t.12**, **2,085,960,145 bytes**, **1819 archive entries**,
SHA ef8f13a98f3a9d4baed93a160e5fb1c0292d48ed10b9a3b2b1e9f347d55eedbe.
package-source-12.json/package-12-byte-proof.json: 13 matching W/K/T Lua sources, unchanged
5 native payloads. **verify2-features-02 PASS 82/82**, driver/checker exit 0, 160 simulated
seconds including all three real K B checks. Yaw/pitch/roll errors .001903/.061300/.001140
degrees; max settled spin .27946 degrees/s. The 183 factor observations all match 0.8.
Image-derived alignment .223957/1.207852 internal pixels; visible boundary .488283/1.495685
output pixels. Five native forced paths each remain released for 15 rows. Hands visibly
uses [ ]; tool help/refusal and raw beam image also reviewed. Normal quit/two cycles,
originals restored, 2877 stock depot files verified, user.conf unchanged. No field game ended.
SteamVR unchanged. No T game/driver/prepared transaction remains from this completed run.

Full **Release PASS at fcb7c6a4**, clean source, exit 0, verify2-release.log/json:
35/35 CTest in 43.61 s, Python 29+26+1483=1538 with 3 skips and zero failures, main group
128.313 s. T's 109 cases are explicitly discovered. Only documentation receipts changed
afterward; no production/probe/test change followed the gate. Scope audit: 41 owned files,
zero foreign files. No need to repeat this gate without a source change or concrete failure.
Final conventions pass (verify2-doc-check.log). No T driver/game/prepared state remains;
all three shared lock/pending paths were absent when checked (verify2-leftovers.json).

Next: await Claude's review and explicit C-landed notice. No Index/C adaptation until
Claude explicitly says C landed. When instructed, merge accepted vr2 INTO v4t only, read C's
frames, adapt only private poses, run a NEW package (v4t.13 if unused) and fresh simulation
before final Index on the same package. All historical commands/packages below are examples;
do not overwrite used v4t.11/12 or transfer measurements to new inputs. No foreign edits.

## Earlier completed round (historical)

Branch/worktree: v4t at H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4t.
Read VR-V4-T-report.md first; its independent-review section supersedes older prototype
claims. No questions needed. Claude directs/reviews. Do not push/publish/start workflows,
merge outward into vr2/main, edit loader/ or foreign implementations. Configured identity
is SheepyLord <37598021+SheepyLord@users.noreply.github.com>; every commit ends with
Co-Authored-By: Codex <noreply@openai.com>. Do not override author.

## Done and verified

- Reviewed vr2 a35897ce merged into v4t as e4769052, bringing real reviewed W 16a27dd1 and K.
  Only decision-index conflict, both sides preserved. No T-authored loader/native import.
- All eight independent-review findings addressed. Physical stick/trigger rearm claims;
  native forced drops and server attack rearm; live server angular limits; cached-dispatch
  beam cooperation; one switch attempt plus refusal notice/custom clipped icons; corrected
  tool hints/IN_SPEED snapping; cached per-frame presentation; independent physical/image
  evidence with real offset-COM gravity barrel. See report's numbered table and before logs.
- Offline exact suite companion/tests/vr_tools_test.py: 98 passing (83 LuaJIT + 15 Python),
  review-offline-final.log. The full Release gate also verifies the test-only addition for
  throwing-icon cleanup. Independent W stand-in stays offline only.
- Final simulated review-features-06, 160 active seconds including all 60-second features:
  82/82 PASS, driver/checker exit 0, all three B checks (OnPhysgunReload, unfreeze, tool reset).
  Yaw/pitch/roll .03720/.04606/.03066 degrees; push/pull +4.971812/-5.009742 m.
  Tracking/hand/controller/creation/Stop each genuinely force-drop and stay released;
  death releases too. Held wheel trigger uses nothing, fresh press uses once.
- All evidence under out/vr/v4t/review-features-06: tools-acceptance.json, tools-provenance.json,
  console, raw eye/centre/depth captures, timings, frozen private source snapshots, summary,
  protected hashes and clean restoration. 2877 stock depot files verified, no mismatches.
  Both cycles end normally. Field game was absent and not ended. SteamVR left running/unchanged.
- Final Release gate PASS at f26577e3, clean source, exit 0: release-review.log/json.
  35/35 CTest in 56.09 s; Python 29+26+1472=1527, 3 skips, zero failures. Main group
  145.410 s, including T's 98 cases. Only documentation receipts changed afterward.
- No T driver/game/prepared PoC state remains. Final lock/pending marker belongs to C's
  review3/sim-cal-01 (PID 3292 at check), untouched; review-leftovers.json records the check.
  Re-read live state on resume, never rely on this old PID. Documentation conventions pass.

## Current package and source

Normal package out/dist/gmod-rtx-remix-0.0.0-v4t.10.gma, production 47c95bc3:
2,085,956,822 bytes, 1819 archive entries (1818 indexed payload files), SHA-256
b7e5181bf7d62771aa0bfd1ed2aadaa36d89bb5562c8b3663a6dae389a45d755.
package-source-10.json/package-10.log and package-10-byte-proof.json record the build;
8 T + 5 W/K Lua files match source byte-for-byte; 5 native payload hashes match the reviewed
inputs. Review image reader corrected at 70db3ee2; this does not change packaged production.
Subsequent changes are test/docs only. Never transfer these measurements to a later package.
review-scope-audit.json lists 41 owned files and zero foreign changes against a35897ce.
Later vr2 Q merge 59792b60 was observed but not merged into this frozen measured source.

## Failures and why (retain evidence)

All native failures and failing-first logs remain under out/vr/v4t, detailed in the report.
review-api-before-01 proves BOTH DropObject and ForcePlayerDrop release immediately on this
build, but held attack reacquires without a rearm guard. Never claim DropObject cannot work.
Failed creation occurs before native attachment: retain until Tick, then force-drop.
review-linear-trial-01 rejects COM target (.568 m ray error); zero linear contribution
preserves native positioning (~.002253 m). This is a labelled private experiment.
review-features-01: cached engine dispatch bypassed public hook wrappers; use live registry.
Also fix native metatable observers and command-clock phase alignment, not raw timing cuts.
review-features-02: creation-before-attachment and missing capture-camera data.
review-features-03: >4095-ish console record truncation; bounded realm-aware chunks now
validate completeness/counts/duplicates. Partial diagnostics are not acceptance.
review-features-04: actual W nominal muzzle differs from rendered attachment by 4.369035 units
(10.9 cm). Reported foreign W issue; T visual beam now uses model attachment, W unchanged.
review-features-05: old image reader ignored measured gun occlusion (86/88 pixels). Original
failed log retained; corrected colour/depth reader passes with unchanged strict limits.
Its screenshot exposed custom icon overflow, now clipped and freshly proved in run06.
Older release timing/space failures and compressed/deduplicated evidence are historical in
report. No evidence cleanup is currently needed (~400 GiB free). Never delete failed evidence.
Automatic approval previously rejected deletion of the old unused runtime and never-launched
v4t.pre GMA; those files remain compressed, not removed. Do not bypass that rejection.

## Exact next steps when work resumes

1. Check status/identity and main checkout's out/r10/poc.lock and vr-poc-pending.json, plus
   out/vr/vr.lock and process command lines. Never touch a foreign C/K/Q transaction/lock.
   If an OWNED session is live let it finish, do not kill it. Only an owned stale prepared
   transaction may be rolled back using tools/vr_session.py --rollback and its matching evidence.
2. If the final Release receipt has not yet been recorded, run tools/test.ps1 -Config Release
   with output under out/vr/v4t, retain exit/source receipt, then update report/note and commit.
   Do not repeat a passing gate without source change or a concrete unresolved failure.
3. Await Claude's independent review and **explicit notification that C has landed**.
   DO NOT adapt scripted poses to unreviewed C and DO NOT run Index before that notification.
   Any new findings get failing-first owned tests, own-file fixes, new package and fresh proof.
4. When instructed, read accepted C/Q reports and git log vr2. Merge accepted vr2 INTO v4t only
   with normal identity/trailer. Never merge a task branch directly. Keep measured v4t.10
   native/source fingerprints separate from new inputs.
5. Adapt ONLY T's private scripted poses to C's documented raw/hand/aim frames. Existing
   identity raw poses assume a level aim and are deliberately unchanged. Production uses
   W/core/model frames and should need no controller-specific constants. Preserve private
   inactive-heading guard and exact m_yaw save/zero/restore; during active VR W/K own input.
6. Run offline suite, build a NEW unused version (v4t.11 if free), record source/native/Lua
   bytes, run simulated full review case in a fresh folder. Require every check, including
   all three real K B checks, independent draw/capture and forced drops. Never fake a pass.
7. After C and simulation pass, final Index proof on that exact package with BOTH locks,
   capturing actual SDK overlay sources/counters/timings. SteamVR stays running and unchanged.
   Record this as final component proof only; Q/user own combined/worn milestone approval.
8. Final Release gate after new integration/code, report, clean commits. No push/outward merge.

Commands (NoProfile PowerShell/login:false selects installed Python 3.12 + Pillow):

```powershell
git status --short
git log -8 --oneline vr2
python -m unittest discover -s companion/tests -p vr_tools_test.py -q
python tools/build_package.py --version 0.0.0-v4t.11 --require-nlctl --json
python companion/tests/vr_tools_poc.py --tools-case review --seconds 160 --simulate --evidence out/vr/v4t/review-after-C-01 --package out/dist/gmod-rtx-remix-0.0.0-v4t.11.gma
python companion/tests/vr_tools_check.py out/vr/v4t/review-after-C-01
tools/test.ps1 -Config Release
# OWNED stale prepared transaction only, no live owner:
python tools/vr_session.py --rollback --evidence out/vr/v4t/OWNED-RUN
```

The driver waits for both shared resources as needed and normal-quits/restores itself. The
main out/vr/v2/quit_field_game.py only requests normal quit and refuses when another PoC
session owns the lock; abort/rollback on its nonzero result. Never force-kill a field game.
All scratch/evidence under out. View one large centre/eye image per tool call (IPC limit).

## Open dependencies

No user clarification. C's accepted frames/final Index, Claude's review, later Q integration,
W nominal-muzzle discrepancy and Q/user combined acceptance remain external. T's current
pre-C production, simulated component proof and full Release gate are complete.

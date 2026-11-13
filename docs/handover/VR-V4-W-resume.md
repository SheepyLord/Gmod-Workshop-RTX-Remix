# V4 task W resume — 2026-11-11

Worktree: `out/worktrees/v4w`, branch **v4w**. The user requested packing up and stopping.
Do not start another milestone or merge/push/publish. The repository git identity is
already configured; never supply another author. End commits with
`Co-Authored-By: Codex <noreply@openai.com>`.

## Current state

**All ten independent-review items (1, 2, 5–12) are implemented and verified.** The
remaining step before this pause was committing the completed fixes/report. This resume
note and all changes are committed together. No W implementation or validation job is
left pending. Claude's final review/integration remains separate.

Read the review section of [VR-V4-W-report.md](VR-V4-W-report.md), then only the code needed
for a new finding. Do not reread the entire V4 brief or print whole JSON/log files.

Changed production files are **cl_weapons.lua and sv_weapons.lua**, with sidecars, W tests,
the report and [decision 0193](../decisions/0193-vr-weapons-after-independent-review.md).
C's protected gun-angle/foregrip and poseGrip regions are unchanged; cl_weapons_model.lua,
sh_weapons.lua and loader/ are unchanged. `out/vr/v4w/review/scope-checks.json` verifies it.

Important implementation details:

- Melee uses tracked linear velocity plus angular velocity cross wrist-to-tip, with
  discontinuity/proxy/locomotion reset guards. Artificial walking/snap/teleport cannot swing.
- Only initial bullets within five units of GetShootPos are redirected. Other starts,
  including missing-geometry penetration/impact passes, remain untouched.
- Native dispatch retains its original function reference. W owns the EntityFireBullets
  event table, forwards the held hooks once, and lets the outer gamemode run once. Global
  hook.Call is unchanged. Additions/removals, cancellation and later writers survive.
- Server tracers have explicit starts and prediction-filter bypass. Local initial
  predicted tracers are suppressed; feedback 65 asks for no duplicate host tracer.
- Launch sounds/animation callbacks follow native creation after PlayerPostThink. Five
  native classes relocate at tick 0. The frag's body is held at the hand while native
  initialization finishes, then its captured throw/spin resumes before physics or at Stop.
- Bugbait is non-VPhysics and has no ready launch callback. Its uninitialized interval
  is hidden; the first ready tick 1 moves it and sets EF_NOINTERP before showing it.
  The first visible native position is 0.03005 m from the launch hand. Do not call this tick 0.
- Impact needs a precise surface trace: the hull centre ends short. Inward skin and full
  start/entity/surface/hitbox-bone/damage fields produce the verified decal. Model decals
  are enabled only for the VR session, restoring only W's last owned value.
- MuzzleEffect uses explicit coordinates. Captures must wait one Source frame after
  effect creation; immediate requests read the previous scene and falsely show no flash.
- Foregrip geometry/permission is a profile; engagement and gun-angle updates do not pause
  firing. Exit changes selection only from Hands, with highest-weight owned fallback.

## Completed evidence

All paths below are relative to this worktree under **out/vr/v4w/review/** (git-ignored).

- **82 offline cases pass**: 79 actual-module LuaJIT plus three evidence/timeline cases.
  `offline-final-05.log`.
- **Full affected simulation**, `sim-after-06`, package **v4w.17**: 22 phases, 98 active
  seconds, 28 capture sets, **7,449 matched rendered frames**, 0 submissions/Submit errors/
  unmatched poses/Lua errors; W and production acceptance true, normal quit and clean rollback.
  44 actual native pellet traces plus six zero-spread diagnostics; zero source error.
  Foregrip bursts: 208 SMG and 209 shotgun commands, zero dropped attacks.
- **Final precise Impact verification**, `sim-impact-01`, package **v4w.18**: 30 active
  seconds, both melee classes, 10 capture sets, **2,448 matched frames**, both acceptances
  true and clean rollback. v4w.18 differs from the full run only in the precise Impact
  contact refinement. Before/after captures visibly show the new dark crowbar decal on
  the crate's centre beam; sparks/particles and 5/20 m muzzle flames are visually verified.
- `final-qa/` contains review sheets. Original captures are unchanged.
- Both selected runs preserve protected hashes and verify **2,877 depot files**, with
  zero missing/size/hash mismatches. Their `restoration.json` and `snapshot/rollback.json`
  are clean. No Index rerun was requested or performed for these corrections.
- **Final Release gate passes, exit 0**: `release-final-02.log` and
  `release-final-02-result.json`, finished **2026-11-11T22:43:05.9421752Z**. 34/34 CTests;
  Python suites 29 / 26 / 1,153 tests, nine skips including K/T's explicit pending suites;
  W's 82 tests included. Earlier Release receipts remain too.
- Repo conventions and whitespace checks passed after the report update, before packing up.

**Current package:** `out/dist/gmod-rtx-remix-0.0.0-v4w.18.gma`, 1,811 files,
2,085,729,694 bytes, SHA-256
`8da5d93b5f6d2295836c88715d3dfffaf53ca59b05a3e487d80e0bc0cca80569`.
`package-final-audit.json` verifies all four W Lua files equal current source and no test
fixture is packaged. Superseded W GMAs were deleted as requested; source snapshots remain
in `retired-sources/`, with their package metadata and failed-run receipts retained.

## Failures retained and lessons

The report lists each failed regression log. In particular:

- `sim-after-02`: fixture placed a 0.7 s step after 0.8 s; startup refused. A monotonic
  native-timeline test now covers the full timeline and foregrip subset.
- `sim-after-04`: replacing global hook.Call worked in the old harness but missed the
  engine's cached dispatcher. The cached-reference test and native traces now cover this.
- `sim-order-01/02`: measured actual native initialization, including the frag's continued
  initialization after its spawn sound and bugbait's lack of VPhysics.
- `sim-after-05`: steady foregrip geometry was captured during cosmetic recoil; the burst
  now finishes before the steady capture. Also exposed bugbait's eye-position first
  display and the overly distant crate fixture; both were corrected and retested.
- `impact-surface-before.log`: the hull-centre endpoint missed the actual decal surface.
  Final Impact verification above proves the contact correction.
- `.12` and the first `.13` queued preflights were cancelled before acquiring the PoC;
  their cancellation receipts/logs remain. They never prepared or ran a game.

`lock_poll_driver.py` is a temporary uncommitted helper in this evidence folder. It calls
the ordinary W driver, only capping the original exclusive-lock retry sleep at 0.1 s
instead of 3 s while acquiring. Acquisition, owner/token, timeout and release remain the
production implementation. Its synthetic contention/acquisition/later-writer tests pass.
This avoided starvation between other agents' runs; it does not steal or remove locks.

## Leftovers at pack-up

No W-owned python driver, PowerShell helper or game remained in the process inventory.
All W sessions/gates had completed; no W restoration is outstanding.

The **main checkout's** `out/r10/poc.lock` names **VR-V4-K reload**, PID **66220**.
`out/r10/vr-poc-pending.json` names that same PID and evidence
`out/worktrees/v4k/out/vr/v4k/sim-empty-01`. PID 66220 was not live when inspected.
**This is K's state: it was left untouched for K/Claude, not restored or removed by W.**
The shared `out/vr/vr.lock` was absent. Recheck ownership on resume; these observations
are a timestamped handoff, not permission to act on another task's files/session.

## Exact next steps on resume

1. Read this note and `git status --short` / `git log -1`. No W process needs restarting.
2. Check shared ownership if any live work is needed; leave K/other tasks to their owners.
3. Have Claude review this committed correction and coordinate C's controller-frame
   changes. K/T combined runs and Q's milestone/user acceptance remain outside W.
4. Do **not** rerun games/builds/gates merely because the thread resumed. Current W
   validation is complete. If a new finding requires code changes, reproduce it first,
   fix it outside C's protected regions, and run only affected simulated phases first.
5. Build a new package version before a new native run; never overwrite v4w.18 or reuse
   an evidence directory. After testing the new version, remove superseded own GMAs.
6. Re-run the final Release gate for new source changes, update the report and commit.
   Never push, merge into vr2/main, publish or start a GitHub package workflow.

Useful commands **only when new work warrants them**:

```powershell
python -B -m unittest discover -s companion/tests -p vr_weapons_test.py -v
python -B tools/build_package.py --version 0.0.0-v4w.<next> --require-nlctl --json
py -3 -B companion/tests/vr_weapons_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4w.<next>.gma --evidence out/vr/v4w/review/<new-run> --seconds 98 --camera 0,0,512,0,0,0 --weapons-phases pistol-5,pistol-20,357-5,smg1-5,ar2-5,shotgun-5,bolt-eye,bolt,rocket,smg-grenade,ar2-orb,fore-smg,fore-shotgun,melee-slow,melee-fast,melee-stun,frag-throw,bugbait-throw,hands,respawn,left,bullet-passes --simulate
python -B companion/tests/vr_weapons_analyse.py out/vr/v4w/review/<new-run>
tools\test.ps1 -Config Release
```

Use installed `py -3` for the game driver (Pillow); normal Miniconda `python` for offline
tests/gates. If lock contention recurs and the temporary helper still exists, substitute
`out/vr/v4w/review/lock_poll_driver.py` for the ordinary driver, with identical arguments.
No packages were installed. The original Index acceptance at 27c509b5 remains historical;
do not represent it as testing this correction.

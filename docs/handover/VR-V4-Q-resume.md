# V4: Q hands over to Claude

The user stopped Q deliberately on 2026-11-12, about18:15 local. **Claude now owns
finishing V4. Q must start no more runs or write product code.** This handover supersedes
the older status checkpoints. The [V4 report](VR-V4-report.md) is still a draft and its
last running-status paragraph is stale; the actual full attempt ended as described here.
Historical checkpoints remain in git through32c9b4b7 and raw evidence remains intact.

All paths beginning `out/vr/v4q` below are relative to this worktree:
`H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/worktrees/v2q`.
The rerun brief is the **main checkout's** `out/vr/v2/msg-QV4-rerun.md`.

## Safe state and packing commits

At the packing audit: no PoC gmod.exe, no Q VR/medium/full runner, neither shared lock,
and no `out/r10/vr-poc-pending.json`. No restoration was necessary. The running field
game and its helper processes were left untouched; they are not Q's processes. No
SteamVR operation was performed during packing. Never remove a foreign lock.

- `c35ba1bf`: completed the interrupted **test-only** finger/carry witness checkpoint.
  No shipped product code changed. Native validation of this checkpoint is pending.
- `a2206016`: packing audit caught/fixed the new carry guard using trigger bit2 instead
  of grip bit1. Executed boundary test fails before, passes after; no game was started.
- Both commits passed `python -B tools/check_repo.py` and `git diff --check` beforehand.
  Final affected suite:36 tests, OK; `out/vr/v4q/round5/handoff-affected-tests-final.log`.
  Earlier35-test packing log and grip-bit failing log are retained alongside it.
- This handover is committed separately. No merge, rebase, push, publication, workflow,
  other-worktree edit or loader edit was performed during packing.

## A-J status against the rerun brief

`d3a87533` is the main round5 correction commit after the authorized fast-forward to
`032c80e7`. Later corrections below are essential; do not use d3a alone as the candidate.

| Item | Status / commits / retained tests |
|---|---|
| A: grip and orientation | **Partly done.** Product measured handle table restored in d3a87533; full raw geometry, independently annotated handle envelopes/centrelines and bone-relative bounds replace the circular bone mount. Generator has no copied CAPS; shaft sections derive from geometry. Stunstick full-ring data corrected.15 placement/orientation mutants are killed, including reversed/rolled pistol, reversed AR2, magazines, barrels, muzzles, stocks,3cm shift and SMG fallback/skew. Tests: `test_remaining_stock_grips_against_independent_posed_mesh_points`, `test_independent_mesh_witness_kills_placement_and_barrel_mutants`, `test_no_product_cap_constants_or_pruned_geometry`, `test_generator_opens_only_declared_raw_sources`; harness `q4_stock_grips`.8f0aa1a3 tightens standalone5mm helper and observes every gun barrel;2974254c adds native Annabelle phases/muzzle requirement in both hands. **Current native both-hand grip captures and Index validation have not run.** |
| B: ladder sectors | **Done, committed and limited-native tested.** d3a87533 implements22.5degree8-way sectors, with tiny numerical boundary allowance. `f_ladder_sectors` covers0/3/5/10/20/22.5+/-.001/45/67.5 and neighbors/90 degrees, head0/-45 and four quadrants; non-ladder vehicle bits stay unchanged. `f_movers_armed_medium_parity` now expects no side bit for.02 against3 forward. d130773e fixes placement of Intent into `move(cmd)` rather than overlay paint; `q5_ladder_overlay_pipeline` fails before/passes after. E04 shows0side bits and0lateral drift for5degree input. |
| C: underwater noclip | **Done, committed and limited-native tested.** d3a87533 gives noclip precedence in cl_move/core/shared basis. `q5_noclip_underwater` covers water0/2/3, armed/unarmed, stick-only0 and hand throttle; `f_noclip_water_basis` covers bypass of client/server basis adaptation. E04 compares real underwater(level3) and land controls. |
| D: beam wording | **Done.** d3a87533; `test_harness_uses_truthful_beam_source`. It is the add-on's beam draw; only the model attachment named core is independent. |
| E: expanded medium | **Done:33/33 pass**, recorded in32c9b4b7. See detailed evidence/results below. |
| F: physgun ladder input | **Done/offline.** d3a87533 moves movement intent before tool commands; neutral main-stick distance input adds no Use on ladders. `q5_ladder_distance` tests no climb-induced push and real push/pull; `f_ladder_tool_buttons` checks core preserves post-movement tool buttons (stock and ULib). Native T/ladder validation is not claimed. |
| G: decision baseline | **Done.** d3a87533 uses merge-base(main,HEAD), not live main. `test_unmerged_main_decision_does_not_change_baseline` and `test_decision_index_preserves_main_and_adds_only_table_rows`. No new main-only documentation was copied to chase a moving ref this round. |
| H: manifest safety | **Done.** d3a87533. Explicit pins verify immutable depot bytes before snapshot/registry or rollback mutation; bad/empty/unverifiable inventories fail, and explicit pins cannot combine with no-depot-check. `test_wrong_explicit_manifest_rejected_before_registry_or_snapshot_write` executes real verification on generated mismatching bytes; missing-pin test retained. Normal drivers pass no old261104 pins. E04 restoration verifies2878 files against installed field manifests. |
| I: report corrections | **Requested round4 corrections done; final V4 report remains unfinished.** d3a87533 and later checkpoint docs; `test_round4_result_records_changed_setup_and_field_limits`. Corrected bugbait/rig contradiction, x=0 scope,5degree amplitude versus1.04..1.26degree sampled spans, changed small-stick expectation, Annabelle-X,45736 self-exit, one ladder-pitch rule, water lag and attempt16 setup changes. Current full results still need Claude's report update. |
| J: quit policy | **Done operationally/guard tested.** Round5 helper calls were only through drivers. `test_field_quit_crash_exit5_stops_before_any_game_launch` retains the existing fail-on-nonzero behavior. Never call the helper by hand. The current main-checkout helper waits120seconds process age and reports post-quit crash as exit5. The user's packing instruction specifically forbids Q ending the current field game. |

Camera duplicate nit is also done in d3a87533: restore removes exactly one owned token,
leaving a foreign identical token; `camera_two_writers` fails before/passes after.

## Expanded medium proof (32c9b4b7)

Accepted evidence: `out/vr/v4q/round5/medium-sim-04` on PoC261112, frozen r5.2 candidate.
**PASS33/33:**15 ladder trials (including six5degree up/down trials), six water trials,
six underwater noclip trials and six land noclip controls. Hands/pistol+45/pistol-45
are included. Both locks held; permanent gm_construct ladder803/water330; no world
target was created/removed. Poses scripted, nobody wore the headset.

- Neutral view90degrees; ladder lateral displacement0 and side bits0.
- Maximum world-wish direction error1.82915e-5degrees.
- Maximum water physical planar error2.888716degrees under the unchanged3degree bound.
- Noclip stick-only speed0; throttle wish112.49996..112.49997Source units/s,
  equal across the three weapon modes and land/water. Measured mean flight speed is
  112.49996..112.49997Source units/s.
- Normal quit,0 Lua/module failures, no native crash, clean restoration of2878 stock
  files. No old manifest pin was passed.

Failed attempts remain: medium01 foreign-lock timeout before preparation; medium02
move-module failure from command-only work wrongly in overlay paint (fixed d130773e);
medium03 passed all movement checks but failed neutral yaw118.5vs90 (fixture initializer
had been stripped, fixed1ff9ae80). No native crash occurred in these attempts.

## Full-run checkpoint: failed attempt and interrupted follow-up

`out/vr/v4q/full-sim-r5-01` stopped after its first `v2v3` role, exit1. The renderer
passed; normal quit,0 Lua/module failures and clean restoration. Physics, movement and
menus groups passed. No crash receipt was produced. **The full sequence did not pass.**

`v2v3/combined-acceptance.json` failed `independent_review` and `tracked_curls`:

- `review-acceptance.json`: `verify_carry_setup`, `7_blink_carry`, `7_shift_carry` failed.
  Only hold had a successful setup row; blink/shift control.grip was false after the
  wall/death/respawn phase. They moved the player, but no carried prop was proved.
  Exact cause was not established. The interrupted follow-up releases grip for.5s
  after each Hands selection before pressing, respects the weapon-release latch,
  requires the actual grip bit before public Grab, and records client owner/class.
  **Whether this fixes native carry is unverified.** If still false, inspect those
  diagnostics and control-message/lifecycle state; never force the mask or success.
- Delivered curl values matched requested values. The old check inspected one Euler
  pitch/yaw component and assumed old axes; C retargets model-specific curl axes.
  c35ba1bf records actual engine GetBoneMatrix parent-relative rotations, not planned
  renderer matrices or motor command angles. It adds an open/splay0 reference after
  the unchanged near-hand poses, then closed targets; it keeps.05 input and1degree
  deflection bounds (thumb40*c, other proximal joints75*c). Missing/stale/model-mismatched
  witnesses fail. Legacy scalar bends remain diagnostic. **This new native witness
  and reference timing have not been validated in a game.** Do not replace a failed
  actual-bone witness with its product command values merely to pass.

The new helper is `companion/tests/vr_finger_witness.lua`, privately inlined by the
combined fixture, never packaged. Its draw-observer predecessor is restored on cleanup.
Affected offline tests (36) pass, including engine-cache versus command-angle checks,
axis-independent rotations, no-draw/wrong-amount/missing/stale-frame mutants, fresh
carry-grip sequencing, and grip-bit1 versus trigger-bit2 preparation.

The failed run also measured the diagnostic overlay worst case:21 visible/native
handles and16 distinct source requests per Source frame. Module bound32 and runtime
pending-source bound16 are unchanged. This is **partial failed-run evidence**, not a
completed current Index/full acceptance result.

No full-sim-r5-02 or current Index run was started. That fresh full simulation was
what Q would have tried next after reviewing the follow-up; the user instead handed
the work to Claude. No run is queued and Q must not resume it.

## Candidate and clean native build

Current candidate: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2q\out\dist\gmod-rtx-remix-0.0.0-v4q.r5.2.gma`

- GMA SHA-256: `b82aea49a113b96e9e471488d81858d69d9f8600191afaac05bdd26d9cc581ca`.
- Payload source: `d130773e659294aaeaa3ba25fbd3dd5bbbce92cb` (d130773e). Later changes are test-only.
- Verified **inside the archive**: fixes module
  `a2f091abdcf8528469b52fdd853abfcb8e1026f5301da26137ad7398805743ab`.
- VR image inside archive: `c5cb2a4844fa38e560639182063765619f3f8f816186ce2b52edd65478049e4d`.
- Build record now names clean `d3a875338f8123dc9af075feb2e5487c80b83114`, without an uncommitted qualifier;
  committed in ab635b8c. CPP sources have not changed since that build.

The VR target was cleaned and a real Release build ran from the clean d3a87533 tree.
The first refresh skipped unchanged source hashes; only the obsolete VR provenance
entry was then invalidated and regenerated using `repo_builds.py refresh nl_vr_client
--build-dir .../out/build/win64-release`. Its verified same-image comparison kept the
stored binary; no direct inputs.py import was used. Logs: round5/native-clean-build.log
and native-record-refresh.log; prior ledger saved as pins-before-refresh.json. The
fixes part/pins remained the accepted ones. `check_repo.py` passes.

The read-only clock helper was rebuilt at `out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll`;
identity: round5/inspect-identity.json. The full recipe defaults to this path.
Failed r5.1 candidate and its receipt remain; only r5.2 is the current candidate.

## Exact future commands for Claude (not queued or executed during packing)

Review the unvalidated finger/carry checkpoint first. These folders were absent at
handoff; use another fresh suffix if needed. Scripts acquire both locks themselves.
They can invoke the guarded field-quit helper, so honor the user's current field-game
direction before executing them. Never call that helper manually.

```powershell
python -B companion/tests/vr_combined_session.py --case full --fixes-reviewed --simulate --package out/dist/gmod-rtx-remix-0.0.0-v4q.r5.2.gma --evidence out/vr/v4q/full-sim-r5-02
```

Only after the simulation passes, check SteamVR is up **and the headset is ready**.
Q has not performed this readiness check or any current Index run. Leave SteamVR
running/unchanged; do not treat a service-process check alone as headset readiness.

```powershell
python -B companion/tests/vr_combined_session.py --case full --fixes-reviewed --package out/dist/gmod-rtx-remix-0.0.0-v4q.r5.2.gma --evidence out/vr/v4q/full-index-r5-01
```

The19-role recipe covers v2v3, allmotion, temporal, armed flight, all-module hooks,
then both-hand geometry/weapons/reload calibration/physical/button/empty/tools. Geometry
now includes W's16 classes plus Annabelle in each hand, with130seconds for17 phases.
Keep eye, near-hand and overlay captures; inspect their semantics and pictures, not only
module health. Controllers may be off: scripted/recorded frames do not validate live
finger tracking, physical haptic feel, human grip comfort or wearer comfort.

## Open tests, evidence and remaining work

- No known failing affected **offline** test at packing:36 passed. Log:
  `out/vr/v4q/round5/handoff-affected-tests-final.log`.
- Product checkpoint d130773e had eight suites20/20,160 invocations, stable code hashes
  (`round5/repeats/summary.json`). Driver fixture126tests repeated20/20 at1ff9ae80
  (`round5/driver-fixture-repeats/summary.json`). The later finger/carry checkpoint has
  affected offline coverage, **not** another20-run or native certificate.
- Native full acceptance remains failed/open as above. Subsequent motion/temporal/flight/
  hooks/geometry/W/K/T roles and the entire current Index sequence are **not run**.
  New both-hand natural-hold capture distances must be measured; the table below is offline.
- Current-candidate weapons-out measurements and alternating published flat controls
  remain unmeasured. Older six armed Index and ten flat controls used **PoC261104**, an
  earlier named package (see report); do not transfer them to261112/r5.2. Use the
  [measurement](../../tools/vr_measure.py.md) and [flat-control](../../tools/vr_flat_parity.py.md)
  tools as the remaining acceptance needs. Separate CPU and GPU quantities.
- The historical Modern House720 mean eye warp1.00924ms exceeded the unchanged1ms
  reference budget. It remains open; it is not a current r5.2 measurement.
- Draft ADR0194 records the new hold/ladder rules. Claude has not reviewed its number
  or status; the original plan reserved Q0183-0185, so check allocation before merging.
- The full Release gate has **not** run for the round5 final source. Claude's accepted
  base032c80e7 gate is not a gate for these later changes. After finishing acceptance/report:

```powershell
$env:NL_FIXES_CLONE='E:/Modding_Backup/garrys-mod-rtx-remixed'
tools/test.ps1 -Config Release
```

Update the final V4 report/shared status with actual results and honest limits, then
review/commit. V2/V3/V4 still await the user's approval; no outward action is authorized.

## Crashes and classification

There was **no round5 native crash** in the medium attempts or failed full simulation.
All failed evidence remains. Historical Q PIDs49376 and50548, plus reviewed22984/50472,
are the old queued-draw fixes crash; main-checkout `out/vr/v2/crash` and the report retain
its dumps/events. The repaired module is now in the candidate, but the new full proof
has not completed.

Historical **field52744** received Q's manual startup quit and then the reviewed NVIDIA
fault; it was not a clean helper shutdown.45736 exited by itself at14:30:44. Read-only
copies of52744 loader evidence/exit report are in `round5/field-52744`. The recorded dump
is no longer at its source; local dump reclassification was not possible. Its known
NVIDIA classification is Claude's reviewed diagnosis, not a new local claim.

Current shared rule (d3a87533): any fixes stack signature stops, even an unreviewed
module build; only `nvoglv64.dll+0xe622f8` at startup permits one clean-restored retry in
a fresh folder. Unknown/second crash stops. Old receipt flags cannot reauthorize fixes
retries. Tests include `test_fixed_package_never_retries_fixes_signature` and
`test_old_fixes_retry_receipt_cannot_reauthorize_itself`. Exact-PID WER sources stay
read-only. Keep dumps and Application1000 evidence; do not dodge the package with cvars.

## Offline A distances for review

These are **harness/retained261104 raw-export results**, not current261112 native/Index
captures. Exact032c80e7 model-source test fails; diagnostic max grasp error164.31529mm.
Current strict test passes32 model/hand samples, max4.93242mm. Diagnostic baseline rows
were collected with assertions disabled only to observe all models; their receipt marks
that explicitly and never counts it as acceptance. Source: round5/hold-distances.json.
Bone-landmark distances are separate and nonzero; no zero-by-construction bone mount
is used as precision proof. Fine centreline residuals can legitimately be zero by symmetry.

| Model | Grasp right mm | Grasp left mm | Rig landmark right/left mm |
|---|---:|---:|---:|
| camera | 0.00367 | 0.00367 | 36.48 / 70.65 |
| w_357 | 0.59787 | 0.59787 | 18.92 / 57.06 |
| w_annabelle | 0.00000 | 0.00000 | 48.02 / 76.92 |
| w_bugbait | 0.00000 | 0.00000 | 164.32 / 150.42 |
| w_crossbow | 4.20597 | 4.20597 | 51.86 / 86.39 |
| w_crowbar | 0.81008 | 0.83249 | 94.98 / 88.46 |
| w_grenade | 0.00000 | 0.00000 | 36.01 / 78.84 |
| w_irifle | 4.93242 | 4.93242 | 51.39 / 62.02 |
| w_medkit | 0.00000 | 0.00000 | 78.67 / 115.79 |
| w_physics | 2.32584 | 2.32584 | 83.36 / 126.07 |
| w_pistol | 1.24299 | 1.24299 | 21.35 / 66.09 |
| w_rocket_launcher | 1.22631 | 1.22631 | 43.05 / 82.76 |
| w_shotgun | 0.00000 | 0.00000 | 86.96 / 95.41 |
| w_smg1 | 0.31943 | 0.31943 | 31.65 / 60.02 |
| w_stunbaton | 0.00000 | 0.00000 | 69.25 / 57.42 |
| w_toolgun | 2.64413 | 2.64413 | 14.16 / 57.03 |

# VR V4 C: raw orientation, physical grips and live-use corrections

Branch `v4c`, 2026-11-12. Follow-up to `adf44a5f`. This report supersedes its grip-target placement claims. All work is branch-only; recorded references and frozen package measurements are identified below.

## Fixes and regressions

| Item | Fix and test |
|---|---|
| 1. Raw left orientation | The shown anatomical frame remains thumb-up independently of the weapon's authored wrist. Both hands get the holding-wrist basis conversion. `uncalibrated_thumb_up` uses measured c_arms frames and actual pistol/SMG/AR2 mount angles; it fails before at up.z=-0.985. `left_grip_basis` again requires thumb-up rather than mirroring the wrong basis. Calibrated and explicitly raw right/left views are captured. |
| 2. Independent grip | A gun's source grip is model-owned: named grip attachment, model finger bones, or a mesh grip-region midpoint. The six real-model points were selected from posed mesh geometry, not VR targets. The validator transforms the independent bone-local point from the DRAWN entity's hand mount, and compares it with a grasp centre calculated from the DRAWN hand's middle-finger bones, every gun frame/capture, limit 20 mm. It never reads `geometry.gripPos` or `Model.Pose`'s target. `independent_grip` fails against the old placement. Mount-to-wrist distance is always reported separately; it is not labelled physical grip error. Empty-hand sweeps have no gun-grip result, not a zero result. |
| 3. Placement versus stability | Wrist/palm motion and transported roll are retained as stability checks of the fixed attachment/hinges, not independent placement evidence. `palm_axis_distance` measures the actual rendered wrist/knuckle palm midpoint against the installed body.obj axis, both hands; a deliberately displaced hand fails the new unit check. The 50 mm envelope is for that bone-centre point, not skin contact: the unmodified baseline was 42.2–43.3 mm. |
| 4. Unknown muzzle | Every unlisted model infers a signed long axis from bounds through its grip. A muzzle more than 45 degrees off that geometry is distrusted; missing muzzle uses the same bounded inference. `unknown_up_muzzle` fails with an unlisted upward attachment and also tests no attachment. Captured barrel expectations come from posed model geometry observations, not W.ModelData or geometry.barrel. |
| 5. Live use | Full skeletal samples now follow each rendered frame with reusable buffers, unchanged-payload detection and last-good retention. Unusable raw frames skip full SDK reads. `render_rate_sampling` fails against the old 30 Hz cap. Property/device-update events refresh component fingerprints, preserve identical geometry/revision and never derive anchors from live curled fingers. Changed geometry uses GripLimit reference landmarks. Native battery-style regression changes live landmarks by 9 mm and requires unchanged hand, wrist, revision and skeletal-read count; it fails before the fix. |
| 6. Real tip-only case | `tip_only_aim` composes a real partial-component frame through cl_frames (Pico-style -30.3-degree raw pose). Production then has equal target/aim angles; W stays level. The inconsistent artificial target-angle case was removed. This is test correction for an already-correct production composition path. |
| Draw allocations | `draw_target_pool` fails without persistent targets. The draw path reuses 31 target vectors/tables and performs one numeric rigid transform; unused per-bone Angle payloads and their two pose conversions are gone. |

Failed-before logs: `weapons-before.log`, `hands-before.log`, `native-before.log`, `frames-before.log`, `palm-before.log`, all under `out/vr/v4c/review3/`. The prior rounds' regression tests remain. Offline tests never read SteamVR files or start a game.

## Independent geometry and measured limits

The weapon world models expose only a right-hand bonemerge mount, not fingers or a named grip. A simulated geometry-read session exported their posed mesh points. `mesh-pose-read/model-bones.json` and `mesh-pose-read/grips-xz.png` evidence and `companion/tests/fixtures/vr_weapon_grips.json` identify the selected handle/stock regions, vertex counts, model-space midpoints and independently transformed bone-local coordinates. The source geometry SHA is in that fixture. The selected region has geometric/semantic uncertainty; micrometre registration errors below are numerical alignment to the selected point, not a claim of micrometre physical accuracy. Synthetic models with real grip attachments/finger bones use those directly.

| Frozen-16 witness | Captures | Physical grip max | Left / right palm-axis max | Raw thumb-up minimum |
|---|---:|---:|---:|---:|
| `sim-raw-01` | 42 | 0.00809 mm | N/A: no known hand frame | 1.000000 |
| `sim-final-01` | 40 | 0.00408 mm | 45.771 / 45.426 mm | calibrated SDK reference |
| `index-final-01` | 40 | 0.00408 mm | 45.771 / 45.424 mm | calibrated SDK reference |

Required physical-grip limit: 20 mm. Palm bone-centre envelope: 50 mm in calibrated Index views. Every gun/holding hand has actual rendered grip samples; missing values fail. No gun-grip number is assigned to empty sweeps.

`sim-final-01` stability only: wrist **0.000 mm**, palm **4.310 mm**, adjacent transported roll **1.405 degrees**, minimum finger travel **142.498 mm**.


`index-final-01` stability only: wrist **0.469 mm**, palm **4.310 mm**, adjacent transported roll **3.254 degrees**, minimum finger travel **142.503 mm**.



The model's hand-mount marker and the rendered avatar wrist are different landmarks/rigs. Their distance is reported for every gun, including when a physical grip point is available. It must not be substituted for the physical grip comparison or hidden by the old `weapon_grip` branch. Mount-marker maxima: `sim-raw-01`: 91.904 mm; `sim-final-01`: 66.096 mm; `index-final-01`: 66.096 mm. These larger bonemerge-mount offsets are retained transparently, including the left-handed and raw paths; physical-grip registration is the separate <20 mm check.

Placement still rests on SteamVR's recorded reference transforms, selected model grip geometry and the reviewed side/top captures while controllers are off. No live hand-size/contact ground truth is claimed. The Index-specific constant correction remains 11.906/12.147 mm (derived from the earlier 22.013/22.293 mm raw cylinder discrepancy); other controller models get zero Index correction, with SDK/component hand frames or the raw fallback. Wrist-local reference registration and fixed hinges intentionally establish stability, not placement.

## Evidence and verification

- `sim-raw-01/{frames,frames-checks,summary,restoration}.json`: 10349 measured render samples, sampling/storage **0.0000 ms/frame**, bone builds **0.3250 ms/frame** (both hands, diagnostic observer included); maximum stable-phase grasp refits 0, weapon measurements 0.
- `sim-final-01/{frames,frames-checks,summary,restoration}.json`: 12370 measured render samples, sampling/storage **0.0154 ms/frame**, bone builds **0.6349 ms/frame** (both hands, diagnostic observer included); maximum stable-phase grasp refits 0, weapon measurements 0.
- `index-final-01/{frames,frames-checks,summary,restoration}.json`: 10020 measured render samples, sampling/storage **0.0117 ms/frame**, bone builds **0.6022 ms/frame** (both hands, diagnostic observer included); maximum stable-phase grasp refits 0, weapon measurements 0.

Side/top images are in each witness's `captures/`: `frames-{pistol,smg}-{left,right}-{side,top}-controller/centre.png`, `frames-smg-{left,right}-fore-{side,top}-controller/centre.png`, and `frames-sweep-{left,right}-{side,top}-{0,1,2,3}-controller/centre.png`. Raw views are explicitly labelled in frames-fixture.json. `sim-raw-01` also includes all generic real-model cases. Earlier `sim-cal-01` used frozen package 15 and is retained as a separate preliminary witness; its numbers are not transferred to package 16.

One Index reference run only, after successful simulations: **11915 rendered/submitted/matched pairs**, 0 Submit errors, 0 unmatched poses, **69.753 pairs/s** at 90 Hz / scale 0.65.


All production sessions use tools/vr_session.py, normal console quit, protected-file/settings checks and clean rollback. Raw images, geometry exports and failed witnesses remain. Frame-owned draw observers capture the matrices actually submitted with their corresponding controller frame, not a later engine bone cache. Camera transitions are excluded from the fixed-tracking curl interval; tracking constancy is checked separately. No engine hook was swapped.

Frozen package **0.0.0-v4c.16**, SHA-256 `c49857ced97f8f95bbe66b97929022a7f88793c85d05924a435cf4c0329a37b9`; diagnostic composite manifest `d406cc2d7d7025eeb189c6751414ea468746ba32973b4c316b83cae230690ccb`. Native module `c5cb2a4844fa38e560639182063765619f3f8f816186ce2b52edd65478049e4d`, current after `native-import.log`. Offline feature suite **262 tests**, native suite **42 tests**. All source/model hashes and failed evidence remain. Code commit `5b4f0fe1` plus the final follow-up/report commit; vr2 `adb14468` remains merged, with no C loader/catalog delta.

`tools/test.ps1 -Config Release`: **35/35 CTests, 29 + 26 + 1211 = 1266 Python cases**, nine skips, no failures (`release-final.log`). Final conventions/provenance check follows report creation.

The first full gate had one mocked publication-fingerprint assertion fail (`release-first.log`); all 42 publication tests passed in isolation, then the complete gate passed with source/HEAD held fixed. No publication occurred.

No field game needed ending. Both shared locks were waited on; no foreign lock or stale-crash archive was touched. SteamVR stayed running and unchanged. There was no push, merge into vr2/main, publication, workflow or C loader edit. Removed 2 owned superseded GMA builds; 4171820493 bytes; all evidence folders retained

## What is open

Live controller status: {'left': {'valid': False, 'device': 4294967295.0, 'model': ''}, 'right': {'valid': False, 'device': 4294967295.0, 'model': ''}}. Controllers remained off; the run replays recorded SDK Open/GripLimit/Fist/WithController fixtures through the actual per-frame reader. Raw live SDK results are retained separately as skeletons_live. Successful live finger tracking, valid-live-SDK timing, other controller hardware and anatomical skin-contact ground truth remain open. The measured mesh-region point has selection uncertainty; reviewed captures remain part of placement acceptance.

Arbitrary models with no grip attachment, finger bones or measured grip profile retain a bounded mount fallback; physical contact for those models is not validated by this six-model fixture. Q must rerun integrated K/T after review and rebuild native provenance if merged native sources change. The earlier reports remain in git; numerical measurements are not transferred between frozen packages.

## Integration of vr2 59792b60 (2026-11-12)

Merge commit **57c42e4d**, parents `d68a66a1` and `59792b60`, integrates W's reviews, K physical reloads and Q's V2/V3 fixes. No merge into vr2/main, push, publication or workflow was performed; no Index run was performed for this integration.

- `cl_weapons.lua`: W's ULib-aware takeover prefix, copied-dispatch re-entry guard and gamemode-return handling remain byte-identical to vr2. Its foregrip permission/profile identity and host-authoritative enable/ack synchronization win the sync conflict. C's grip/trigger latches and resets, holding-hand-only grasp invalidation, anatomical pose and rendered grip observer remain. Foregrip held/blocked/climbing guards remain. All three declaration/sync/startup conflict regions preserve both sets of state.
- `cl_hands.lua` guards from Q remain: pending/visible ghosts are hidden once and cancelled. The harness conflict retains both C's sampler/anatomy/render-rate regressions and Q's pending-ghost regression, using Q's pending-overlay stub.
- `vr_weapons_test.py` retains every C case plus W's review, third-review, stock/ULib/unknown-library and evidence cases. Documentation conflicts retain both descriptions. The decision index retains every former link/entry in numeric order.
- Q's server `pose.vel` / `wvel` split, player-relative melee, server bullet handling and `cl_interact.lua` are byte-identical to vr2. Core view ownership/cache changes are retained alongside C's single frame-composition call. K's main-A claims remain; C adds no main-A claim.

Only `vr/native/README.md` changed relative to C's pre-merge native tree. The module **c5cb2a4844fa38e560639182063765619f3f8f816186ce2b52edd65478049e4d** and its source record remain current; no rebuild/import or provenance rewrite was needed.

Offline evidence: `out/vr/v4c/merge-companion-vr.log` **508 cases**; `merge-tool-companion-vr.log` **509 cases, one skipped**; `merge-core-vr.log` **94 core/framework cases**; `merge-tool-vr.log` **57 driver/integration cases**. Hands, weapons, reload, V4 scaffold and V2/V3 suites are included; tools has no implementation in this branch and its bridge skips explicitly. The first parallel bridge run exposed a shared writable temporary pose fixture; per-case owned fixture directories fixed that race, then both direct/bridge suites passed concurrently.

One simulated production set, fresh `out/vr/v4c/merge5979/sim-01/`: **32 passing captures**, both hands, calibrated/raw, pistol and SMG foregrip, side/top; maximum rendered grip registration **0.00809 mm**, minimum raw thumb-up z **1.000000**. The near-zero registration remains a consistency check because placement uses the same selected grip region; accuracy rests on SteamVR's recorded references and the captures until live controllers are on. All required foregrips engaged; zero Lua errors, normal quit, original settings/protected files restored and clean rollback. Images: `captures/frames-pistol-{left,right}-{side,top}-controller/centre.png`, `frames-smg-fore-{left,right}-{side,top}-controller/centre.png`, and corresponding `frames-raw-...` folders. The raw left SMG side view and calibrated right SMG top view were visually checked after the merge.

Frozen measured package **0.0.0-v4c.17**, SHA-256 `ca423fd86bf4f8f5c1a25e29560ee74ca97b4fc94cfdea64a19a05ce7e8d08f6`; composite manifest `f785deedb559238724c5e580f2ade53c8ec7dc12787f51d6005703f962935bdf`. No prior-package numbers were transferred. Source/model hashes and the fresh receipts remain with the witness.

`tools/test.ps1 -Config Release` passes: **35/35 CTests**, **29 + 26 + 1481 = 1536 Python cases**; see `out/vr/v4c/merge5979/release-final.log`. The native binary/provenance is unchanged and current. Shared locks were waited on; no foreign lock was removed. SteamVR stayed running and unchanged. No field game needed ending. After verifying the tested package and its production-file hashes, only C's superseded v4c.16 GMA was deleted (2,085,912,889 bytes); `cleanup-builds.json` records the checks. All evidence remains.

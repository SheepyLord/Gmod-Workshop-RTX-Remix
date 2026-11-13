# VR V2, V3 and V4: integration report

## Final: approved and merged (2026-11-12)

On 2026-11-12 the user had Q (Codex) pack up at about 18:15 and asked Claude to finish V4 itself: "finalize V4 for a
deliverable at this stage, build the VR module and package and push to main and workshop". After Codex's hand-over
([VR-V4-Q-resume.md](VR-V4-Q-resume.md)) the user said go. This section is the final state; everything after it is
the branch's history, kept as evidence.

**What V2-V4 deliver** (all of it stays off until **RTX Remix > VR > Start VR**; the controls are under
[What these branches deliver](#what-these-branches-deliver)):

- **V2:** hands and fingers from the controller frames, wall ghosts, movement and turning, teleport and comfort
  settings, room-scale following, height calibration, wrist menus, spawn/context panels, the escape menu and keyboard
  input on laser panels.
- **V3:** physical hand contacts, one- and two-hand grabbing, throws, gravity gloves, ragdoll handling, Use by touch,
  climbing, melee and haptics.
- **V4:** world weapons held in the hand and shot along the gun from the muzzle, foregrips, physical reloads, the
  ammunition shown on the gun, a weapon wheel, and hand-driven physgun and toolgun controls.

**How it reached `main`:**

- `v2q` at `505deb4a` (Q's last commit) fast-forwarded into `vr2`; `main` at `5e72cd26` (the Loading-enhancements
  texture cache, runtime patch 0086, [ADR 0195](../decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md))
  merged into it as `625406fb`.
- **Runtime:** one build of patches 0001-0086 (VR's 0072-0085 and main's 0086) from the clone's `vr2` at `308ca2f7`:
  `d3d9.dll` 418,444,288 bytes, SHA-256 `7572e10453a386093eac75e0fa8424d53bfbbdeced163b8c15534a03390cb9d6` (`bfd1fe3a`).
- **VR module:** a clean rebuild of `nl_vr_client` from the final sources is the same image as the stored
  `gmcl_nlvr_win64.dll` (539,136 bytes, SHA-256 `c5cb2a48...`; `repo_builds.same_image`), so nothing was re-imported.
- **Package:** the tested candidate is `gmod-rtx-remix-0.0.0-v4final.4.gma` (the code of `6eb9759b`), 2,086,362,912
  bytes, SHA-256 `032760a056cc244dfa574e3c9d69a528d74a51597f6c234adc4586a2751df752`, content digest `b60de134...`,
  checked by `nlctl`. Inside it: `native/payload/runtime/d3d9.dll` `7572e104...`, `gmcl_nlvr_win64.dll` `c5cb2a48...`
  and the repaired fixes module `gmcl_RTXFixesBinary_win64.dll` `a2f091ab...`
  ([ADR 0192](../decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)). `v4final.1`-`.3` were the same
  but for the motion predictor. The published build is recorded at the end of this section.

**What the final package's runs showed** (PoC on GMod 261112, simulated VR session unless noted; poses scripted, nobody
wore the headset; evidence under the `vr2` worktree's `out/vr/v4final/`):

- **First full run, `v4final.1`** (`full-sim-01`): the combined V2/V3 section passed, including the two checks that had
  stopped Q's run (a carried prop after the death/respawn phase, and the finger curls measured from the engine's bones).
  The motion section then failed its camera-smoothness check. Q's own last package (`r5.2`) fails it the same way
  (13.6/21.6/23.8 % for walk/sprint/flight against 10 %), so it was V4's, not the merge's.
- **Motion fix** ([ADR 0196](../decisions/0196-vr-motion-keeps-the-wires-cadence.md)): the camera held for a frame
  whenever the motor buffer changed and starved after every reset. Results, walk/sprint/flight spread and stalled frames:

  | Package | Spread % | Stalled frames |
  |---|---|---|
  | `v4final.1` (two runs) | 13.1/25.4/21.8 and 17.5/46.3/21.7 | 6 and 3 |
  | `v4final.2`: cadence kept, 5 % easing | 12.0/11.3/13.4 | 0 |
  | `v4final.3`: and a two-second hold | 11.1/4.1/8.5 | 0 |
  | `v4final.4`: 2.5 % easing, ten-second hold (shipped) | 8.0/11.6/9.7 | 0 |

  The camera no longer stops; the remaining spread sits around the 10 % bound from run to run. Most of it is pairs of a
  long and a short measured frame with equal camera steps: the probe's `RenderScene` time jitters against the view
  call's motor time. V2/V3's package measured 0.6/0.5/1.5 % on 2026-11-11.
- **Second full run, `v4final.4`** (`full-sim-02`, every section run without stopping):

  | Section | Result |
  |---|---|
  | Combined V2/V3 (hands, physics, menus, movement) | Passed in the first run. In the second only "cursor restored after Exit VR" failed, a check that a mouse or focus change during the run breaks |
  | Motion | Walk/sprint/flight 8.0/11.6/9.7 %, no stalled frame (see the table above) |
  | Temporal | Not measured: the test driver refused the section's timeline as larger than 1 MiB (V4's controller profiles are in it) |
  | Flight | Passed |
  | Hooks (add-on lifecycle, ULib dispatch) | Passed |
  | Geometry, right and left hand | Sessions passed; every class's muzzle within 1 cm. The only missing check is the Annabelle's independent muzzle emitter, a requirement Q added in its last round and never ran in the game |
  | Guns, calibration, reload, button, empty (right hand) | Failed the driver's fixture check before their own: the neutral view faced 0 degrees (45 for guns) instead of the requested 180, so the shooting targets were not at the required range. No Lua or module error in 1,000-10,000 frames each. K's earlier reload runs faced 180 and passed, so this is a regression of the test fixture's view set-up, not established for the product |
  | Tools (physgun, toolgun, wheel), right hand | Passed |
  | Left-hand guns, calibration, reload, button, empty and tools | Not run: the sequence was stopped after the left-hand geometry, as they share the right hand's fixture problem |

- **Claude's look at the geometry captures** (`out/vr/v4final/review/hands-right-sheet.jpg` and `hands-left-sheet.jpg`):
  every stock gun, the Annabelle, the physgun, toolgun, camera, crowbar, stunstick, grenade, bug bait and medkit sits
  at its handle in the closed hand, in both hands; round 4's guns beside the hand are gone.
- **Index** (`index-combined-01`, the combined V2/V3 section on the real headset and SteamVR, scripted poses, nobody
  wearing it): passed every check (renderer, physical, movement, menus, the independent review's carry, finger
  curls from the engine's bones, held locomotion, near-hand coverage at 20, 30 and 50 cm, accounting). 7,588 eye
  pairs were rendered and submitted with every pose matched, no submit error and no dropped frame; at 43 pairs per
  second on gm_construct (2,468 x 2,740 per eye) SteamVR reprojected 8,643 of its 15,972 presents. The session's
  Start VR started SteamVR at 22:03; it was left running.
- **Release gate** on `6eb9759b` (the final code; later commits are documentation): `tools	est.ps1 -Config Release`
  passed, 35 of 35 CTest and 1,821 Python tests (one skip), "All checks passed".

**The second review's items (A-J, rerun brief of 2026-11-12):** all were fixed with failing-then-passing tests; the
details are in [VR-V4-Q-resume.md](VR-V4-Q-resume.md).

| Item | Result |
|---|---|
| A. Guns in the hand | The measured handle table is back (byte-identical to the one round 4 removed). Offline, every stock gun's handle centre is within 5 mm of the closed hand in both hands (worst AR2, 4.93 mm; round 4's version was off by up to 164 mm); reversed and rolled pistols, a reversed AR2, magazine, barrel, muzzle, stock and 3 cm placements fail the test. |
| B. Ladder strafe | 22.5-degree eight-way sectors on ladders only; a stick 5 degrees off straight gives no side button and no lateral drift (limited PoC check). |
| C. Noclip under water | Noclip wins over swimming in the client, core and server basis; flight speed is the same under water and on land. |
| D-J | Beam wording, the 33-case limited PoC check, physgun on ladders (no push while climbing; pushing on a ladder still climbs), the decision-index baseline, the manifest pins (fail closed), the report corrections and the field-quit rule are done. |

**Still untested or open:**

- Nobody wore the headset. Every pose was scripted or recorded; live finger tracking, haptic feel, grip comfort and
  wearer comfort are untested.
- Only the Index's bindings were exercised; the Touch and Vive bindings are untested.
- Guns, calibration, reload, button and empty were not validated on the final package (the fixture problem above),
  nor anything in the left hand except the geometry; W, K and T validated them on their own branches before the
  integration rounds.
- The temporal section was not measured (the timeline size limit).
- The Modern House eye warp measured 1.009 ms in round 4 against a 1 ms reference budget; not re-measured.
- Weapons-out performance and alternating flat controls were measured on earlier packages (PoC 261104), not on this one.
- Pushing a held prop with the physgun while on a ladder also climbs (the distance command uses the same buttons).

**Published:** squash-merged into `main` as `7a149d76` (tree `a96ac4ef`, the tested `vr2`'s) and pushed. The commit's hook
uploaded the package to item 3829070317 as `0.0.0-dev.20261113050849+df868432` (2,086,362,930 bytes, SHA-256
`fe86c234f6df76a28e9bab1c4e9ab2ea4bac39dcdc355e02f3f46f38636ddbfd`, content digest `b60de134...`, the tested `v4final.4`'s
digest, so its content is the candidate's); the push's hook found the inputs unchanged. The field gets it at its next
start (Steam's update of the item).

## Round 5 integration (history; Q stopped at the user's request)

**E now passes:** `round5/medium-sim-04`,33/33 cases on frozen r5.2 (SHA below), PoC261112.
Neutral yaw90; ladder5degree input has zero side buttons and lateral drift; max world-wish
error1.82915e-5degrees. Water physical planar error max2.888716degrees under unchanged3.
Idle noclip is zero; throttle flight112.49996..112.49997units/s, equal for Hands/pistol+/-45
and land/water. Normal quit, no Lua/module failure/native crash; all2878 stock files verify
clean against installed field manifests. No old pins. Full simulation is now running under
`out/vr/v4q/full-sim-r5-01`; the Index sequence has not started. Driver-only fixture checks
were repeated20/20 after the neutral initializer correction (126 tests each).

Fresh r5.2 candidate (Lua movement-callback correction), source d130773e, archive
SHA b82aea49a113b96e9e471488d81858d69d9f8600191afaac05bdd26d9cc581ca, carries the
same verified fixed module. Medium03 completed all33 movement trials with no module
failure/native crash and clean2878-file restoration. All medium-specific checks pass:
5degree ladder input has zero side buttons/lateral drift; idle noclip is zero; throttle
flight is112.5units/s, equal for Hands/pistol+/-45 and land/water. Overall it is still
**FAILED**, because the generic neutral-camera check saw118.5degrees instead of90.
The moving probe had stripped the pre-start fixture view initializer. A retained
executed-hook test fails before restoration of the initializer and passes after; the
high-priority fixture hook clears physical mouse deltas before core but does not replace
active VR views or scripted movers. The.5degree neutral check is unchanged. Retry E in
a fresh folder before any full sequence. The8 affected suites passed20/20 at d130773e
(160 invocations, stable hashes); the later fixture-only correction is rechecked separately.

Candidate r5.1 was built from ab635b8c with clean VR source provenance d3a87533.
Archive SHA a3687fc417736959c1eb99c2ff3410aa42d39ee5c20406db9103aa5eea08caf5;
its fixes DLL is exactly a2f091abdcf8528469b52fdd853abfcb8e1026f5301da26137ad7398805743ab.
Medium01 timed out on a foreign PoC lock before preparation. Medium02 ran on261112,
then failed: my ladder command stamp was in before_overlay_paint, where cmd is nil,
so the move module stopped. Only the first case produced probes; the remaining
readiness checks timed out. This is a failed test, with evidence retained, normal quit
and clean restoration; **no native crash**. A retained real overlay/movement lifecycle
regression fails before the correction and passes after moving the stamp into move(cmd).
A new r5.2 candidate is required; r5.1 is not a successful acceptance package.

Fast-forwarded to accepted `vr2`032c80e7. The queued-draw repair is integrated in source;
W's decision is0193. Full combined acceptance is authorized after A-J and the expanded
limited medium proof pass. Offline regressions for A-D/F-H and the camera duplicate
pass, including15 rejected weapon placement/orientation mutants. The failed medium02 run is recorded above. Evidence is `out/vr/v4q/round5/`. New PoC is build261112 (field buildid26623711);
old261104 depot pins are not used. Earlier261104 figures below are historical and are
not transferred to this rebuilt install or the forthcoming candidate package.

## Round 4 evidence corrections

Only attempt16 of 16 limited medium attempts passed, on PoC261104. Before that pass,
the gun observer changed from converged eye command to the rendered barrel, water
settling changed from.8 to1.5seconds, and ladder start heights/crouch setup changed.
The attempts are not identical reruns. Original failed evidence remains intact.

Zero side buttons/drift in medium-sim-16 covered **exactly x=0 input**, not imperfect
thumbstick input. Five degrees was the scripted yaw amplitude; actual within-case
head-yaw spans were1.04..1.26degrees. Small-input offline tests then expected full-speed
side buttons; round5 deliberately replaces that expectation with22.5degree8-way sectors.

Water physical planar error was2.85..2.93degrees against the unchanged3degree bound.
The desired world wish follows the current head within.2degree; Source water velocity
has acceleration/friction lag while the head continues rotating (up to10degrees/sec).
Settling removes startup acceleration, not this continuing physical response delay.
The3degree bound measures that velocity response, separately from the much tighter
command-direction test. It is not relaxed in round5; both quantities stay in receipts.

Round4's bone-mount change had **no post-change in-game grip captures**. Its precise
zero bone residuals were circular and did not prove the handle was in the fingers.
The claim that bugbait sat in the grasp was wrong for that change: the actual rigs'
landmarks differed by16.43cm. Round5 restores measured mesh handles and independently
checks complete raw mesh/handle envelopes, finger circles and rendered orientation.
The rig residual is reported separately and is not forced to zero. Annabelle's authored
barrel direction is-X; it was omitted from the earlier axis table.

PID45736 exited normally **by itself at14:30:44**; the second helper log says no game
was running. PID52744 received my by-hand quit during startup and crashed1-4seconds
later in the NVIDIA driver, per Claude's reviewed dump diagnosis. The loader records
0xC0000005 after5.68seconds of process lifetime. This was a field crash, not a clean
helper shutdown. The manual quit was a mistake. Its loader evidence/exit report is
retained read-only under `round5/field-52744`; the named5.3MB dump is no longer at its
recorded source path, so no new local dump reclassification is claimed. The reviewed
classification remains NVIDIA startup fault. No round5 quit helper is run by hand.
The current driver-only helper waits for120seconds process age; exit5 after a quit
crash is fatal to the calling test. A retained test verifies that exit5 stops preparation.

## Round 4 results (historical; corrections above apply)

## Second independent review of d6f2ba15

The fixes-module repair has not been confirmed in Q's package. **No full combined
simulation or Index sequence is permitted or has been run.** This review uses frozen
`v4q.review4`, SHA-256 `6772601adf69554cdd901c75e582cc76d1a5790906846d52b09aab04c7b7937d`,
whose payload comes from `dadf9feb`; later fixture/test/document changes do not alter it. Earlier
Index/flat/performance numbers below belong to their earlier named payloads and are
not transferred to this one. Evidence for this review is `out/vr/v4q/review2/`.

| Finding | Retained failing-before / passing-after witness |
|---|---|
| 1. Hand draw gate order | `q4r_dispatch_peer` first asserts the peer is really at HOOK_MONITOR_HIGH. Old wrapper fails deterministically; all trailing hook.Add arguments now pass through. `small-before.log` / `small-after.log`. |
| 2. Ladder side drift | `f_server_ladder_yaw_intent` covers accepted-head versus command-yaw differences .05, 1 and 5 degrees, forward speeds200/3/.02/-3 and side0/+/-.02. Digital buttons are stamped from command intent before gun projection, never recreated from a later head sync. `move-before.log` / `move-after.log`. |
| 3. Armed water/ladder parity | `f_movers_armed_medium_parity` uses head-45 and gun+/-45/unarmed; `q4s_medium_head_rule` drives real L/Core with conflicting off-hand yaw. Water follows head pitch/yaw. Ladders preserve normal Source head-directed climbing: looking up plus Forward climbs up, Back reverses it; the gun never steers the climb. `locomotion-before.log` and `move-before.log` fail; `move-after.log` passes. |
| 4. Camera token leak | `camera_two_writers` now rejects a leaked owned negative hash after append/replacement, preserves foreign tokens, and keeps exact saved-value restore when unchanged. `camera_visibility` agrees. Screen cleanup remains unconditional. `small-before.log` / `small-after.log`. |
| 5. Trigger-only pickup | Both-hand `q4s_trigger_claim_item`: a menu-owned trigger does not consume a free healthkit grab; no Use fires. Watch-only contact tracking returns false. `small-before.log` / `small-after.log`. |
| 6. Grip/axis independence | The new authored-bone test fails old inferred midpoint placement (`rig-before.log`) and passes the fix (`rig-after.log`). All14 non-shafts use the model's authored holding-hand bone versus the rendered Hand bone; there is no grip box or frame.grip target. Barrel/muzzle relocation and old SMG X-fallback mutants are rejected. `axis-bound-before.log` / `axis-bound-after.log`. |
| 7. Beam label | The baseline fails `test_observer_beam_is_labelled_addon_and_core_is_the_independent_reference` (`beam-before.log`). Evidence now says observed_addon_cl_tools_beam_draw. **Only the asset attachment named core is independent**; comparing T's own draw is an additional consistency check, not an engine witness. Earlier engine/convention labels are retracted, original receipts retained. |
| 8. Native quit bound | Executed `test_quit_native_deadline_after_page_off` fails when page-off hides native-stopping at26s, then passes the25s deadline applied to both sides. `small-before.log` / `small-after.log`. |
| 9. AGENTS status | `test_agents_has_one_short_vr_status_outside_repo_map` fails the status history/paragraphs inside Repo map, passes one short linked VR paragraph. The vr/ table row is unchanged. `docs-before.log` / `docs-after.log`. |
| 10. Shared index | `test_decision_index_preserves_main_and_adds_only_table_rows` fails the rewritten table, passes main's exact content plus30 VR table rows. The current main...HEAD index diff has37 additions and0 deletions (including main's own newer additions). Missing referenced main documentation is copied unchanged; no main code or merge is brought in. `docs-before.log` / `docs-after.log`. |

The fixture generator is checked in as `companion/tests/vr_mesh_fixture.py`, with complete
regeneration commands in its sidecar. It opens only declared raw JSON measurement
exports; no sh_weapons.lua, cl_weapons_model.lua, cl_weapons_mesh.lua, reported palm frame
or product grip value is read. Hand binding is recovered from actual rendered hand bones
and physical hand poses. The authored holding-bone agreement bound remains20mm; this
checks Valve's rig mount, not an invented mesh grip midpoint or a human comfort result.
The two shaft witnesses retain their separate geometric/finger method.

SMG's front-cap normal is `(0.99946459, .03271786, -.00028281)`, tilted1.875 degrees from
X. Its20 raw cap points have maximum plane residual3.38e-6 authored units. With a
conservative1e-4-unit export allowance and .295-unit transverse spread, the deterministic
angular uncertainty bound is .0402degrees. The new .1degree agreement bound supports
that fit and rejects the old X fallback; the old2degree bound is not retained. This is
a geometric error allowance, not a statistical confidence interval.

Actual product axis selection, in authored model coordinates (`weapon-axes.log`):

| Gun/tool | Axis used |
|---|---|
| Pistol, AR2, shotgun, RPG, Annabelle | Authored `-X` |
| .357, crossbow | Authored `+X` |
| SMG1 | Posed barrel-ring fit `( .99946476, .03271270, -.00028614 )` |
| Physgun | Model core attachment forward, effectively `+X` |
| Toolgun | Model muzzle attachment forward, effectively `+X` |

All seven affected suites pass **20/20**, **140/140 suite invocations**, on final code
`8bf0b962` with stable code hashes (`repeats-accepted/summary.json`). Each invocation
passes core203, hands26, weapons157, interaction66, movement57, frames30 or
shared-driver114 tests. No further order-dependent result was observed. Earlier complete20-run snapshots
remain under `repeats/`, `repeats-final/` and `repeats-complete/`. The first final-source
attempt (`repeats-verified/`) correctly failed the index preservation check after main
advanced to include ADR0192. Main's new lines and referenced documentation were then
restored unchanged. This was a moving-main documentation failure, not Lua dispatch order.

The limited real-ladder/water PoC and its observer mutations/compiled Lua pass. It targets permanent gm_construct world brushes803/330, creates/removes
no world target, does not force ladder type/water level and retains normal weapon/Exit
cleanup. It always requests both locks. The final limited run is `medium-sim-16`: **all15 cases pass**, Hands/pistol+45/pistol-45,
real ladder up/down/idle and head-directed water up/down. It used both locks, scripted
head yaw with5degree amplitude (observed case spans1.04..1.26degrees), ordinary V2 physical crouch for the short ladder's lip,
and normal Source physics. All measured samples are unfrozen; no ladder type/water level
or physics result is forced. Ladder lateral displacement and side buttons are **zero with exactly x=0 stick input**.
Up/down/idle travel is18/-27/0 Source units in each mode; max world-wish direction
error2.081e-5degrees; accepted-head versus command head sync differs by up to.3866degrees.
Armed/unarmed desired speeds agree within.25unit/s and physical mean velocities within
2units/s. Water's fixed1.5second settling precedes ten samples; all bounds are retained.

The 1degree gun bound measures the actual rendered pistol barrel (-model forward).
Eye-command convergence is a separate angle: W keeps the gun along the controller but
aims the player's command from the eye toward the gun ray's target. Earlier fixture
attempts incorrectly treated those as the same. `barrel-vs-command-before.log` fails
that assumption; the new contract and successful native run retain the same1degree bound.
No production aim/model result was overridden to obtain this proof.

All failed attempts remain.01 failed imports before preparation;02 failed staging path
before launch;03 timed out on a foreign lock.04/05 used bad approach/aim feedback;06
exposed the incorrect yaw-only ladder rule;09..15 refined valid inputs/setup/observers.
07/08 aborted before launch when a field game existed. PID45736 exited by itself at14:30:44. PID52744 received the old manual helper quit
during startup and then crashed in NVIDIA; see the corrected field history above.
No Q native crash occurred. Foreign locks were never removed. Ordinary weapon-switch
and Exit cleanup remain unchanged; all world targets are permanent map geometry.

The field install updated to261112 while PoC remains stock261104. Recovery04 initially
compared against the field's new manifest, then successfully verified all2877 stock
files against the PoC's official cached revision (4001_8532700529041238050 and
4002_4618021864461761722), with zero missing/resized/changed files. Explicit manifest
pinning is now supported by snapshot/rollback and the shared driver, with fail-before/
pass-after tests; verification is never skipped and Steam files are never written.
All subsequent runs restore cleanly against those pins. Raw receipts keep this history.

Final Release gate `tools/test.ps1 -Config Release` **passes**:35/35 CTest;
1781 main Python tests (5 skips), auxiliary29 and26 (1 skip each). Log:
`out/vr/v4q/review2/release-accepted.log`. The repository conventions, full source tests
and diff whitespace check pass. No loader change, push, publication, workflow or merge
was made. The final resource audit has no live locks/pending transaction; SteamVR
PIDs35804/29960 remain unchanged. W's decision 0191
was renumbered 0193 when main was merged into vr2 (main holds 0191 and 0192); the shared index still
preserves main exactly and adds only rows (37added/0deleted relative to the merge base;
30 VR rows relative to current main). Missing referenced main
documentation was copied byte-for-byte, including the queued-draw repair report and its
sidecars; no main implementation or merge was imported. Main now records that repair,
but Q's tested payload still lacks it and Claude has not authorized the full rerun.

## Previous review and retained evidence

## Current independent review (2026-11-12)

**Branch-only review draft; V2, V3 and V4 await the user's approval.** Claude's latest
direction supersedes the historical stops below: fix the independent findings, run only
limited overlay/hook checks, armed Index measurements and alternating VR-off controls.
The complete simulated and Index sequences remain forbidden until Claude confirms the
separate fixes-module repair. No fixture removal or lighting/cvar workaround was used.

V2 delivers tracked hands, movement/comfort and laser menus; V3 adds physical contacts,
grabbing/throws, touch Use and climbing; V4 adds hand-held weapons, reloads, ammo, the
wheel and physgun/toolgun controls. After a reviewed fixed package is provided, start
from **RTX Remix > VR > Start VR**; off-hand B opens the wrist menu and its settings,
and **Hands** frees the hands for physical interactions. Hold main B for the weapon
wheel; a pistol's tap A ejects, off-shoulder grip takes ammunition, and insertion reloads.
The [detailed controls](#what-these-branches-deliver) below remain a branch trial guide.
Full physics trials wait for the separate fix; no field installation was updated here.

Corrected package: `out/dist/gmod-rtx-remix-0.0.0-v4q.review2.gma`, source `595ac82a`,
SHA-256 `ffa1f7592919b75f6cfaf76ff0605552afc8d7e3312febfd857a482c9f5f5bf3`.
Later test/driver/docs changes do not change this payload. Raw evidence for this review is
`out/vr/v4q/review/` in Q's worktree. The preceding package v4q.3 and its measurements
remain separate; its self-referential geometry certificates are withdrawn.

| Review item | Retained failing-then-passing test and correction |
|---|---|
| 1. Melee reach | `q4_real_melee`: both classes/hands with recorded hand frames; actual mesh end versus server tip <=3 cm and hook-only contact causes 65 damage. Reverting to .56/.48 m fails. Production measures posed shaft/grasp/end rather than old grip lengths. `real-melee-before.log`, `real-melee-measured.log`. |
| 2. Independent metrology | `q4_stock_grips` uses raw posed vertices and rendered hand bones, with no product grip table. 20 mm fit and shaft 12 cm envelope retained. Product grip/placement +3 cm, wrong physgun attachment, and real SMG 2.9-degree skew mutants fail. SMG axis fits barrel rings; independent cap-plane normal measures ~1.875 degrees from authored X. Physgun observer requires the asset's named `core` plus actual drawn beam, not a numeric probe fallback; agreeing wrong W/T origins also fail. `mesh-grip-before.log`, `geometry-mutations.log`, `muzzle-strengthened.log`. |
| 3. P/W mutant survivors | `q4r_release_rules`, `q4r_each_use_mask`, `q4r_owned_grab_and_drop`, `q4r_main_mask_off_damage`, `q4r_ownership_death` and `q4r_ownership_dead_tick` assert the missing effects. Eight P and two W mutations are explicitly rejected. Registration AND expiry invalidate collision rules for entity/player. `p-before.log`, `p-mutations.log`, `w-death-mutations.log`. |
| 4. Ending claims | `q4_hand_ownership`/`q4_passive_claims` invert the old assertion: no stale-contact Use when ownership ends, then a fresh contact or actual press works. `q4r_held_press_across_claim` rejects a synthetic held-button edge. Whole-hand ownership suppresses bare hits; an off-hand grip-only foregrip/magazine claim preserves W's previous off-hand damage. Main grip still suppresses it. This follows V4's main-hand ownership rule. |
| 5. Frag feedback | `q4r_grenade_feedback` fails the dead pretend-Grab path; `q4r_projectile_feedback` requires grab and release pulses in both hands and cancellation on death. Dedicated deferred feedback replaces impossible Grab/Release calls; projectile registration remains. `p-haptics-before.log`, `p-haptics-after.log`, `w-haptics-before.log`, `w-haptics-after.log`. |
| 6. Camera lease | `camera_two_writers` now uses the production single active camera and an intervening writer; `camera_screen_cleanup` catches the skipped screen restore. Exact compare-and-restore preserves a writer's `0xccc`; obsolete overlapping lease counting removed. Module-error/Exit cleanup retained. `camera-before.log`, `camera-after.log`. |
| 7. Settle interval | Executed look, test_quit and stopping-second branches all wait one second of native/page off before live selectors. A mutation removing any wait fails. `settle-before.log`, `settle-after.log`. |
| 8. Exercised add-on | `f_competing_addon_lifecycle` dispatches real CalcView/Think/input callbacks across two Starts/Exits in stock and ULib; immediate-removal mutant fails. Limited runtime check requires actual returned head view, both hand draws, movement and a laser menu click, with peers retained across restart. |
| 9. Shared dispatch | P, H and K peer-dispatch regressions fail direct calls, pass `hook.Run`. Entire core harness also runs ULib. Fresh ULib `GetTable()` snapshots and detached PoC import are tested; late Add/Remove operates on the live dispatch tables. `dispatch-all-after.log`, `core-both-after.log`, `poc-import-after.log`. |
| 10. Movement/model keys | `f_movers_ladder_water` and `f_server_ladder_water_basis` fail at +/-45 degrees before shared SetupMove rebase, pass on both ladder/water paths while gun aim remains intact. Physgun model fallback is keyed by `models/weapons/w_physics.mdl`; `q4r_muzzle_world_model` rejects a reskinned unrelated model. |

The earlier focused checkpoint passes **199 core and 646 module/evidence tests**, plus
the shared-driver suites. The final Release gate below includes the added shared
regressions and the entire ULib core bridge (`core-bridge-before/after.log`).
Mutation cases are part of these suites; model numbers above are geometric consistency
results from real recorded mesh/hand frames, not new headset captures or comfort approval.
Crowbar forward reach is .55556 m left / .55542 m right; stunstick .38906 / .38892 m.
The serialized endpoint discrepancy is zero in that fixture, not a claim of physical precision.

### Permitted runtime results and remaining acceptance

`safe-sim-03` passes the limited two-cycle hook/menu/movement/21-role check. Its 21
diagnostic overlay textures include ammo, tool and wheel; peak native handles 21 of 32,
peak distinct source requests in a Source frame 16. The runtime's 16 limit is **pending
requests between drains**, not total live overlays. The per-frame request witness does
not expose a separate internal queue high-water counter. Mutually exclusive canvases
are composed for resource pressure; this is not a natural simultaneous-menu state or
the full all-module feature acceptance. Simulated: 1560 rendered, zero SDK submissions,
zero unmatched poses/submit errors, normal quit and exact restoration.

The first limited attempt (`safe-sim-01`) failed exact settings restoration (`0.6` became
`0.60`) and missed a recreated idle vignette texture. The retained settings regression
fails on the prior code and passes after suppressing numeric-only Derma echoes; real edits
still write. The second attempt restores settings exactly but still lacks that texture.
The third keeps actual movement during capture so the real vignette paints; no declaration
or bound was dropped. These are retained logical failures, not native crashes.

`safe-index-01` passes the same limited checks on the real compositor: all 21 textures,
native/source peaks 21/16, **1622 rendered/submitted pairs**, no unmatched poses/submit
errors, normal quit, exact selectors/settings and clean rollback. Both locks were held.

Armed Index controls use the corrected package above, gm_construct, 1280x720 window,
90 Hz, 2468x2740 per-eye output, 3112x2752 centre and 1556x1376 traced image. They use
the same preset, static natural-frame holding pose, no firing or breakable/removed target.
Each accepts 25 one-second samples in the explicitly defined 10..35-second steady window;
actual class/model and increasing draw count are required, not just requested selection.

| Weapon / evidence | Eye pairs/s | Covered GPU work ms | Elapsed GPU span ms | Game-thread CPU ms/pair | Render-thread CPU ms, short samples |
|---|---:|---:|---:|---:|---:|
| Pistol / `measure-pistol-01` | 45.002 | 12.188 | 19.748 | 7.713 | 5.757 |
| SMG1 / `measure-smg-01` | 45.004 | 12.295 | 19.680 | 7.555 | 5.208 |
| Physgun / `measure-physgun-01` | 45.000 | 12.147 | 19.986 | 7.398 | 0.000, quantized samples |

All three have **50% compositor reprojection, zero dropped presents**. This is about
45 new pairs/s (about22.22 ms between new pairs) at90 Hz, not native90 rendered FPS. GPU figures are means of 19/18/18
covered bracket profiles, not all-frame percentiles. Elapsed GPU span includes gaps and
must not be called GPU work or added to it. The two CPU quantities belong to distinct
threads/denominators and are not additive frame cost. Game-thread accounting measures the
whole game, not a VR-only CPU delta. Windows CPU accounting is quantized;
physgun's short steady render-thread samples all round to zero. Its separately reported
all-lifetime cumulative-average sample mean is 4.080 ms and includes warmup/captures;
it is not substituted for steady CPU. Independent game-thread accounting still measures
7.398 ms/pair. These idle armed controls do not establish firing/reload or human handling
costs. Exact package identity, profile coverage and depth checks are in each
`measurements.json`; raw evidence remains alongside it.

The same armed pistol/preset was also measured across both desktop sizes in both scenes:

| Scene / window / evidence | New pairs/s | GPU work ms | GPU elapsed span ms | Game-thread CPU ms/pair | Eye warp ms | Compositor reprojection |
|---|---:|---:|---:|---:|---:|---:|
| Construct 720p / `measure-pistol-01` | 45.002 | 12.188 | 19.748 | 7.713 | .768 | 50.0% |
| Construct 4K / `measure-construct4k-01` | 44.992 | 12.544 | 19.709 | 7.398 | .863 | 50.0% |
| Modern House 720p / `measure-house720-01` | 29.795 | 17.561 | 27.150 | 15.992 | **1.009** | 67.275% |
| Modern House 4K / `measure-house4k-01` | 31.476 | 17.604 | 22.705 | 15.993 | .989 | 75.581% |

All six armed controls preserve the same package SHA, normal quit, exact restoration,
90 Hz and depth/coverage checks; all have zero dropped presents. House GPU means use
12/13 covered profiles. Centre3112x2752 and traced1556x1376 stay unchanged at both
desktop sizes. Mirror GPU brackets grow from .00840 to .04080 ms (construct), .00890
to .02269 ms (House): this is the required desktop mirror. These single-run timings
include pacing/clock variation and do not establish a 4K speedup or a weapon-only cost.

**Open performance criterion:** House 720p's mean eye warp1.00924 ms exceeds the plan's
1.0 ms reference budget. The criterion is retained; this result does not certify it.
Near0.2m whole-hand acceptance and the complete fixed-package performance rerun remain
pending. House throughput is only about30..31.5 new pairs/s with substantial reprojection;
no human comfort result is claimed. Measurement success means complete evidence/coverage
checks, not that every milestone performance criterion passed.

`flat-01` passes **all ten alternating published/candidate launches** plus every numeric,
image and inventory check. Published control version `0.0.0-dev.20261112034453+d568f6e1`,
SHA-256 `f95f0108eec2339921851a78038f2d813f662d5611e6e296154d4baf06e6ac8b`.
Median of frame medians: published **7.8606 ms**, candidate **7.8469 ms** (delta
-.0137 ms; existing tolerance .3930 ms). Median launch-to-map: **24.2 / 24.3 s**
(+.1 s; existing tolerance2.42 s). Five paired image mean differences .5011.. .6920 DN
are below the unchanged within-published-control tolerance1.6241 DN. All client/server
hook/receiver/timer controls pass; no active VR globals, session hooks or timers in any
launch, only the documented page/stub allowance. These controls find no measurable flat regression
within their precision; these numbers do not mean an exact zero-cost proof.
Every game quit normally and rolled back cleanly; no field game was present or ended.

The private flat child CLI originally lacked a reproducible --evidence argument for
the shared known-crash retry. `flat-retry-before.log` fails that contract; the corrected
CLI and strict recorded/clean/one-use retry selection pass `flat-retry-after.log`.
Unknown, repeated or outside-root attempts cannot replace a failed launch. No runtime
retry was needed in this batch.

**Final Release gate passes** (`release-final.log`): 35 CTest tests; main Python 1757
tests with 5 skips; auxiliary Python 29 and 26 tests, each with 1 skip. The code was
rechecked after the final gated-plan additions. `review-summary.json` indexes all 20
limited receipts (18 pass, 2 retained logical failures), six matching payload hashes,
normal quits/restoration and the open criteria. No loader edit, push, publication,
workflow, outward merge or SteamVR setting change. No PoC game, live lock or pending
transaction remains; SteamVR service PIDs 35804/29960 stayed running.

 The complete V2/V3 Done matrix and V4 points 1-12 remain **unaccepted
as a combined sequence** in both simulated and Index modes; the historical subset rows
below are not promoted. Index controllers are off; all Index work is scripted poses on
the real compositor with recorded component frames, nobody wearing the headset. Live
finger tracking, natural human handling and comfort are unvalidated.

When Claude confirms the fixed package, one command runs all full chapters, their
semantic reducers and both handed settings:

```powershell
python companion/tests/vr_combined_session.py --case full --fixes-reviewed --simulate --package <FIXED.gma> --evidence out/vr/v4q/full-sim-fresh
python companion/tests/vr_combined_session.py --case full --fixes-reviewed --package <FIXED.gma> --evidence out/vr/v4q/full-index-fresh
```

The flag is an operator attestation of Claude's repair review, not permission granted by
this report. Without it full paths refuse before preparing a game. No such full run has
been made during this review. It includes V2/V3, all-module hooks, both-hand independent
geometry, W guns/melee/grenades, K calibration/physical/counter-motion/button/empty-reserve
matrices, T features, allmotion, wall-time temporal movement, armed +/-45-degree noclip,
two-cycle lifecycle and left-handed settings. The retained full-plan regression fails
when these supplemental chapters are omitted (`full-plan-before/after.log`). It requires the built
read-only CPU clock helper (`tools/vr_measure_build.ps1`, default local helper path or
--inspect-dll); absence refuses before evidence/preparation, rather than omitting CPU/
network acceptance. Its generated sources
are offline-compiled; runtime acceptance waits for that fixed package.

All four reviewed native dumps have the pre-existing fixes-module queued-render
freed-entity signature: watermelon gibs in **49376 and 22984**, the crate swung as a bat
in **50548**, and R's deleted cube in **50472**. Source evidence and Claude's diagnosis
are `out/vr/v2/crash/README.md` in the main checkout; exact copied WER dumps and matching
Application 1000 events remain in Q's run evidence. The separate production fix waits
for the user's go-ahead. No native crash occurred in the limited overlay checks, six armed
controls or ten flat launches above. Full combined failures are retained and classified below, not relabelled
as VR defects or hidden by avoiding removals in the full fixtures.

### Historical evidence (superseded status follows)


**Latest state: stopped after the second consecutive pre-existing fixes-module crash.**
Claude diagnosed the first failure and authorized one retry. Shared driver checkpoint
4a376a93 copies WER evidence read-only, classifies from the exception-context stack and
passes 82 offline driver tests. The one retry `combined-sim-02` then failed with the exact
same reviewed fixes signature; `retry_eligible=false` correctly prevented a third run.
This is not a VR defect. No fixture removal or cvar avoidance was introduced.

| Crash / reviewed dump | Classification and action |
|---|---|
| PID 49376, original Q4 run | Known fixes build 0x6af185ec / fault-thread stack return +0x41605b, RSP + 128; WER copy retained; one retry authorized. |
| PID 50548, fresh retry | Same known fixes build/return, RSP + 128, exception RIP0; **second consecutive crash, stopped**. |
| PID 50472, prior R witness supplied by Claude | Same build/return, RSP + 128; read-only classifier confirmation, not a Q4 run. |
| PID 22984, prior witness supplied by Claude | Same build/return, RSP + 176; exception RIP client.dll+0x5744c; read-only confirmation, not a Q4 run. |

The new failure's WER copy is
`out/vr/v4q/combined-sim-02/crash-reports/wer/gmod.exe.50548.dmp`, 362335573 bytes,
SHA-256 `157ced6b372117e8a643dad2f74ea2197bf073610f3a7242b0dd7f0fd8f27549`.
`crash.json` records thread 53620, exception RSP 386895181112 and exact match at 386895181240.
Windows Application 1000 record 39243 at2026-11-12T15:54:04.3876210Z corroborates PID0xc574.
The dump source in the legacy install was never written, moved or deleted.

Last active sample59.383779s:4324 rendered/matched,0 unmatched poses/submit errors;
last physical samplephase 13. The full sequence remains failed; no later chapter or
full worst-case acceptance is inferred. Restoration is clean, locks/pending clear,
SteamVR unchanged and no field game ended. There was no Q4 Index run, weapons-out
CPU/GPU benchmark, alternating published flat batch or final Release gate. C remains
a review draft; B/D remain unfinished. The accepted A results and point-by-point
unfinished B matrix below are retained and have not been relabelled as full acceptance.

An unwired W/K/T dominant-hand adapter draft and 3 pure layout tests were checkpointed;
that groundwork is not a runtime acceptance result. See [crash review](VR-V4-crash-review.md)
and [latest resume state](VR-V4-Q-resume.md) before another preparation.

## Earlier stop report and accepted A evidence


**Stopped after a native crash; branch only, awaiting review and the user's approval.**
This is a partial integration report, not a claim that B's acceptance or the Release gate
passed. Q followed the user's crash rule and did not retry. No Index session was run in
this thread. The physical controllers remained switched off.

`v2q` fast-forwarded successfully to accepted `vr2` **84b0b8c9**. Q's implementation and
test checkpoints are **8f356f7b**, **5e8dcfa1**, **66ac316b**, **c5d0552b** and **5abed1ac**.
The [resume record](VR-V4-Q-resume.md) preserves the individual steps and failures.

## What these branches deliver

- **V2:** controller-frame hands and fingers, wall ghosts, movement and turning,
  teleport and comfort settings, room-scale following, calibration, wrist menus,
  spawn/context panels, escape menu and keyboard input.
- **V3:** physical hand contacts, one/two-hand grabbing, throws, gravity gloves,
  ragdoll handling, touch Use, climbing, melee and haptics. VR leaves Keep corpses alone.
- **V4:** hand-held world weapons, muzzle-based shots, foregrips, physical reloads,
  an ammunition counter, a weapon wheel, and hand-driven physgun/toolgun controls.
  Q adds ten further measured stock grip landmarks and the actual physgun emitter.

After crash review, the manual route is **RTX Remix > VR > Start VR**. The off-hand B
button opens the wrist menu; movement/comfort/height and dominant-hand choices are on
the VR page. Select **Hands** to grab and use, then grip a prop and release to throw.
Hold main-hand B for the weapon wheel. With a pistol, tap main A to eject, grip over
the off shoulder to take ammunition, and bring it to the well; holding A retains the
secondary attack. The physgun uses trigger to pick up, hand rotation, stick push/pull,
A to freeze and tap B to unfreeze. Choose toolgun tools on the spawn panel; A and tap B
retain secondary/reload. Swing melee weapons rather than pressing the trigger.
These are trial instructions for the reviewed branch, not a published field release.

## Frozen package and evidence

All paths below are relative to **this v2q worktree**, under `out/vr/v4q`.

- Package: `out/dist/gmod-rtx-remix-0.0.0-v4q.3.gma`, **1821 files**, **2,086,050,811 bytes**.
- GMA SHA-256: `6cd66136a9fdff0560a70b80d68cc6d1f605ba1c81ebd469ca17bd59fb8a148b`.
- Content digest: `c66912c7554c1a96aac685bc9472adf9ed2f6724eb462f0552a04a6c524bbea7`.
- Frozen product source: **66ac316b**; later commits change observers/analyzers and reporting.
  Native/runtime inputs were not rebuilt or imported by Q. `package-3.log` records nlctl validation.
- Geometry observers decorate the package with private controller diagnostics. Their separate
  manifests/source hashes remain in the evidence; they do not relabel another package's results.

The last complete focused offline run passed **626 VR tests** (`offline-current.log`).
Subsequent barrel/unclassified-reload regressions passed individually; **19 combined/driver
tests** passed (`laser-tip-after.log`). The final complete Release gate was **not run**.

## A: corrections and retained tests

| Item | Result and test |
|---|---|
| Armed noclip 3D rebase | `VRTests.test_f_movers_noclip` failed before, passes +/-45 degrees; ground yaw behavior is retained. `flight-sim-02` passes four actual Source trials, both hands: 467.02--468.68 units (11.68--11.72 m), zero sideways and vertical travel. All 44 sampled commands follow the off-hand direction with pitched gun aim. |
| Shared Stop settlement | `test_shared_probe_settles_flat_cache_after_second_stop` fails before/passes after the shared driver's one-second interval after both native/page off. Per-task duplicate replacements were removed. |
| P claims and W workaround | `q4_passive_claims`, `q4_hand_ownership`, `q4_released_projectile` fail before/pass after. P exposes explicit `ClaimHand` and `RegisterReleased`; passive Use honors both control masks, owned hands cannot perform bare contacts, released projectiles have shared grace. W no longer edits P use/melee cooldowns or vetoes bare-proxy damage. Ordinary thrown props keep immediate API re-grabs; all 57 interaction cases passed after that compatibility correction. |
| Camera restore | `camera_module_failure` verifies W Lua-module exception, cleanup and subsequent Exit. `camera_two_writers` failed before/pass after a shared lease, both release orders; unrelated config changes and a pre-existing negative token survive. `camera_visibility` remains. These are offline restore-path tests, not a forced native crash. |
| Grips after C | Independent posed meshes were exported in `mesh-export-01`. The ten remaining landmarks are in `fixtures/vr_v4_weapon_grips.json`; `q4_stock_grips` failed before at 17.4 cm for the crowbar and passes in both hands after placement correction. All 16 requested classes have 32 captures per hand in `geometry-right-02` / `geometry-left-01`. That earlier capture preceded round4's bone-mount regression; it does not validate the later hold. Round5 restores the measured handle path. |
| Actual muzzle/convergence | `q4_physgun_attachment` failed before/pass after using the known first attachment of w_physics when no named muzzle exists. `q4_rendered_muzzle` covers transformed poses. W's ray/convergence already starts at this exported muzzle, now the same emitter as T. Nine exposed gun/tool attachments were checked in both hands. |
| Shared ULib fixture | Every module harness uses the original shared `vr_hook_fixture.lua`: priorities -2..2, ignored monitor returns, Remove-before-Add and backward-table indexing. The fixture is installed in place as a private test add-on. `integration-sim-02` passes **13/13 integration checks**, all P/W/K/K-assets/T semantic reducers, two Starts/Exits, add/remove during and after VR, all eight modules healthy, zero Lua/module errors, normal quit and clean rollback. |

The ULib contract comes from the [public hook API and documented priority tests](https://github.com/TeamUlysses/ulib/blob/master/lua/ulib/shared/hook.lua);
its implementation was not copied. Core view ownership uses the same fixture and retains its
stock/ULib lifecycle, competing view, detached-dispatch and reentrancy regressions.

## Criterion corrections, with original failures retained

The right-hand geometry run originally failed a universal **12 cm bonemerge-marker to
avatar-wrist bound**: crowbar 18.6119 cm, bugbait 16.4316 cm. Those are different rigs'
landmarks. The replacement keeps the distance visible and requires the independently
selected physical grip within **20 mm**, the closed grasp within **5 mm**, and finite
mount metrology. Missing/displaced grips still fail the new regression. The original
`frames-checks.json` remains; `frames-checks-reviewed.json` is the explicit re-analysis.

Stock `weapon_fists` has an empty WorldModel. Its visible avatar hands are checked; a
nonexistent gun mesh is not required. Every actual modeled weapon retains its strict checks.

The SMG attachment marker is **2.91586 degrees** from its mesh barrel in the retained
combined witness. Replacing the marker with the independently measured mesh axis, transformed
by the actual model angle, retains the **2-degree** barrel bound. Marker orientation remains
reported separately; attachment position and all shot/impact limits are unchanged.

Numerical registration to selected grip regions is **0.00408 mm right / 0.00273 mm left**;
muzzle position errors are **0.00354 mm right / 0.00250 mm left**, at receipt precision.
These tiny figures verify transformation consistency. They are not micrometre accuracy
claims for skin contact: region selection and real hand fit retain uncertainty.

The first flight fixture changed vignette before the flat baseline. It passed motion but
failed the preference guard; `flight-sim-01` remains. The corrected fixture changes preferences
after Start and passes unchanged guards in `flight-sim-02`.

The first all-module witness remains failed as `integration-sim-01`, with original reducers
under `analysis-original`. It exposed pre-chapter unclassified K observer rows, required
provenance/receipt plumbing, T's clear-air arena requirement, and the difference between palm
and SDK tip origin when aiming at a panel. `QFrames.Aim` solves that tip ray without moving the
requested palm; both-hand tests retain the correction. A cached frame-writer predecessor is
also kept alive across later-writer restoration, with a failing reverted-path mutation.
The fresh, accepted `integration-sim-02` does not borrow success from run01.

## Fresh all-module simulation numbers

`integration-sim-02` rendered/matched **8940/8940** frames, with **0 unmatched poses**,
**0 submit errors**, **0 Lua errors** and **0 managed module failures**. It is simulated:
`framesSubmitted=0`; these are not compositor throughput measurements.

- P push/throw semantic checks pass alongside every other production module.
- Pistol: three 5 m shots, maximum observed impact error **3.751 cm**; strict W reduction passes.
- Physical pistol reload: **5.24698 seconds** held empty, no engine reload, correct reserve,
  insertion and fire-again behavior. Counter: **79 matrix samples**, maximum matrix error
  **5.615 mm**, five stable repaint groups; strict K/capture checks pass.
- Physgun maximum settled rotation errors: yaw **0.00257 degrees**, pitch **0.06000 degrees**,
  roll **0.00272 degrees**. Push **+4.97169 m**, pull **-5.00963 m**. Freeze/unfreeze, two beam
  image witnesses, wheel selection/tap behavior, menu-selected remover/colour and A/B actions pass.

## B: Done-point status, without transferring earlier task results

No Q4 Index acceptance was run. Earlier W/K/T/C Index reports remain their own artifacts.
The tables describe fresh evidence here, not completion of the requested full sequence.

| V4 Done | Fresh simulation | Index |
|---|---|---|
| 1. Models/grips/switch/stop | All 16 classes, both hands captured and registered; complete temporal switch/stop/cleanup matrix pending. | Not run |
| 2. Shots/projectiles/wall/punch | Pistol 5 m subset passes; complete gun/range/projectile/wall matrix pending. | Not run |
| 3. Foregrip | SMG subset passes; shotgun and complete both-hand sequence pending. | Not run |
| 4. Physical/button reload | Physical pistol subset passes; all other classes, empty reserves and button-mode sequence pending. | Not run |
| 5. Ammo counter | Pistol matrix/repaint subset passes; complete per-class/both-hand sequence pending. | Not run |
| 6. Wheel | T Hands/crowbar and tap/hold subset passes; complete inventory/both-hand sequence pending. | Not run |
| 7. Physgun | T right-hand feature checks pass with the numbers above; left/full sequence pending. | Not run |
| 8. Toolgun | T right-hand remover/colour/secondary/reload/info checks pass; left/full sequence pending. | Not run |
| 9. Melee | Fast crowbar subset plus offline regressions; complete slow/fast/stunstick/both-hand sequence pending. | Not run |
| 10. Grenade | Frag subset passes strict W reduction; full both-hand sequence pending. | Not run |
| 11. Hands/ownership | P grabs with Hands; explicit armed ownership/claim/release regressions pass. Complete runtime matrix pending. | Not run |
| 12. Death/respawn/Exit/off | Two Starts/Exits, inventories/preferences/rollback pass in A; full death/respawn and published flat parity pending. | Not run |

| V2 Done | Fresh simulation | Index |
|---|---|---|
| 1. Hands/curls/dominant hand | Natural controller-frame and anatomical captures in both hands; full combined bindings sequence not accepted. | Not run |
| 2. Wall/ghost hand | Offline guards and partial physical run; full combined step not accepted. | Not run |
| 3. Movement/turn/room follow | Full combined sequence stopped before this chapter. | Not run |
| 4. Teleport/stance/noclip/scale/comfort | Armed noclip four trials pass; full chapter not reached. | Not run |
| 5. Wrist/spawn/context/escape/keyboard | T spawn-panel tool clicks pass; full UI chapter not reached. | Not run |
| 6. Ghost reduction/near hands | Fresh complete near-hand/ghost comparison not reached. | Not run |
| 7. Exit/zero-off-cost | A lifecycle/restoration passes; complete package flat controls not run. | Not run |

| V3 Done | Fresh simulation | Index |
|---|---|---|
| 1. Push props/ragdolls/NPCs/walls | P push subset passes; complete combined result not accepted. | Not run |
| 2. Grab/heavy/two-hand/throw/spin | P throw subset passes; complete combined result not accepted. | Not run |
| 3. Gravity gloves | Offline suite retained; fresh full acceptance incomplete. | Not run |
| 4. Ragdolls/death ragdoll | Fresh full acceptance incomplete. | Not run |
| 5. Touch Use/items | Claim regressions pass; the full run crashed during door-Use phase 11. | Not run |
| 6. Climbing | Fresh full acceptance incomplete. | Not run |
| 7. Punch/held melee | Offline regressions and partial runtime evidence; full combined result not accepted. | Not run |
| 8. Haptics/death/Exit release | Subset/lifecycle evidence only; full sequence not accepted. | Not run |

### Overlay worst case, timing and flat parity

The combined fixture includes **21 forced roles**, including ammo, tool and wheel. The
native module limit is **32**; the runtime's **16** limit is pending source requests between
drains. Offline resource tests remain. The fresh full run crashed before the worst-case
chapter: **no new all-role compositor/budget acceptance is claimed**.

No new `tools/vr_measure.py` weapons-out CPU/GPU benchmark or alternating published flat
controls completed. Simulated frame counts above must not be presented as Index frame times,
game-thread CPU quantities or measured GPU cost. No older package's numbers were transferred.

## Crash, hard stop and next review

`combined-sim-01` started **2026-11-12 15:01:44 UTC**, PID **49376**, and exited
**0xC0000005**. Windows Application event **1000**, record **39236**, at
**15:03:18.2813828 UTC** matches PID **0xc0e0** and `gmod.exe`; it names module
**unknown**, offset **0**. It does not establish the cause.

The last active probe sample was **49.3693 s**, **3482 rendered/matched** frames, no unmatched
poses or submit errors. The last physics record is phase **11**, the fixture's
`prop_door_rotating` hand-Use case, about **1.785 Source seconds** into that phase. This is
a location in the sequence, not proof that door Use caused the native fault.

No matching minidump was available under the run, PoC, Windows CrashDumps or Steam dumps.
Four older PoC dumps were left untouched. Evidence includes `game.log`, the console,
`application-1000.json`, `crash-classification.json`, `dump-search.json`, the failed subsystem
receipts and captures. This is an active-play crash, not the permitted NVIDIA startup
signature, so **no retry or further test was performed**.

PoC restoration is clean. Both shared locks and the pending transaction marker are absent;
no game remains. SteamVR server/compositor retain their original running process IDs.
No field game was present or ended. No loader source edit, push, publication, workflow or
merge into `vr2`/`main` occurred.

Claude should review this crash before another acceptance preparation. The remaining work
is the full simulated sequence, then the same scripted natural-pose Index acceptance,
worst-case overlays, weapons-out CPU/GPU measurements, published flat controls, final shared
documentation review, and `tools/test.ps1 -Config Release`. V2/V3/V4 remain awaiting the
user's approval; none is marked complete or approved here.


## Claude's crash review and directed resumption

The unknown-cause stop above records what Q knew at that time. Claude subsequently located
Windows' full WER dump in the configured legacy LocalDumps folder and diagnosed the
pre-existing fixes-module queued-render freed-entity crash, not a VR defect. Q's read-only
exception-stack classifier confirms the exact return +0x41605b/build timestamp 0x6af185ec
in49376 and both reviewed earlier dumps22984/50472. The original evidence remains, with
a verified WER copy and crash.json added. The [reviewed rule](VR-V4-crash-review.md)
permits one complete fresh-folder retry; no entity-removal or lighting/cvar workaround.
Claude explicitly directed continuation of B/C/D. Acceptance is resuming, not yet complete.

# VR V2 task L: movement and comfort

Completed on `v2l`, in its assigned worktree. Simulated and Index feature acceptance pass, as
does the Release gate. Final receipts are distinguished from retained diagnostics.
Only task L's assigned files are own changes. No push, merge into main/vr2, publication,
GitHub workflow, loader edit or native binary import was performed by L.

## What is built

| Feature | Implementation |
|---|---|
| Following the head | Horizontal raw tracking translation is consumed once into a sequenced cumulative room delta; the anchor stays under the head. The authoritative server sweeps/slides/steps the current hull in move data. Camera translation comes from the collision-checked feet, with one local-server-tick translation latency. Source still supplies gravity, steps, jumping and ordinary movement. Tracking loss/reacquisition and implausible jumps rebase safely. |
| Stopped head | The play space shifts back with the stopped hull. A 2-unit eye sweep from the engine eye to the tracked head catches solids and a head beyond a thin ceiling; a head-locked full black fade covers blocked room walking and eye penetration. The optional vignette can be zero without disabling safety fades. |
| Walking | Radial 0.2 deadzone, normalized diagonal speed, off-stick direction from hand/head setting, ordinary walk speed, off click sprint and off A jump. Logical main/off roles mirror with the dominant-hand setting. Existing keyboard movement remains available in production. |
| Turning | Main-stick snap with neutral-release latch, configurable smooth turn, and physical mouse delta. Every turn calls F's head-pivot helper. The camera stays at the head; no player-entity rotation/position patch. |
| Teleport | Continuous segmented ballistic hand arc (6 m/s forward, 2 m/s upward, 9.81 m/s squared gravity, 0.04 s segments). Eight overlay dots and a green/red overlay target ring. Release requests blink or a 0.15 s shift. |
| Server validation | Fresh validated physical hand, recomputed arc, target agreement, standing hull/floor, normal at least 0.7, 8 m range, 1.5 m upward mantle. Clear direct routes remain level, including low doorways; a blocked direct route tries up/across/down for a ledge. Every route corner/segment is swept again during movement. Moving obstacles, death, vehicles, movement type or climbing ownership interrupt. |
| Crouch | Physical crouch enters below 68% and exits above 78% of standing eye height. Main-stick down toggles duck. Its standing-to-duck offset blends out continuously as physical height falls, avoiding an upward camera pop at the physical threshold; a deeper physical bend still lowers the eyes. |
| Noclip | Never grants noclip. An existing noclip state flies along the off hand, with exact trigger fraction of run speed. Commands carry the world vector in the current view basis; the server avoids the engine's unrelated noclip speed multiplier. |
| Height/seating | Calibration measures standing tracking height, sets height and matching units/metre, and reports whether another Start is needed. Seated offset is applied to head and hands together; physical crouch is disabled in seated mode. See the native-scale limit below. |
| Comfort/debug/lifetime | Lazy, owned SteamVR overlay canvases for the arc, target, vignette and fade. No perspective UI geometry. Plain debug values expose positions, play space, target/refusal/result, crouch, speed, turn pivot error and calibration. Every hook/receiver/event/mover/canvas is owned by F and removed at Exit. |

Sources are `modules/cl_move.lua`, `cl_move_math.lua` (pure rules shared by both realms),
`cl_move_overlay.lua`, and `sv_move.lua`, with their sidecars. No framework file changed.

## Interfaces for sibling tasks

- M's calibration button can call `NLVR.Move.Calibrate()` or `NLVR.Emit("calibrate")` (also
  `height_calibrate`). Returns `success, {height,scale,restart}` or `false, reason` and emits
  `calibrated` on success. This writes `nl_vr_height` and matching `nl_vr_scale` for the next Start.
  **Native stereo scale is latched at Start and has no live setter.** L keeps current camera/stereo
  scales equal and exposes `calibration.restart` when a new Start is required. The core/page/native
  owners can provide live scale or a controlled restart; L does not change their files.
- P's climbing mover must precede server priority 20 (teleport). Noclip uses 50; room follow 100
  and returns nil so ordinary Source movement still runs. Player state `move` is L's. FinishMove
  discards room input and cancels a pending teleport when a higher-priority mover wins, so letting
  go of a climbing grip cannot replay either. P currently uses priority 5, which agrees.
- Messages 24/25/26/27 are room input / teleport request / result / follow receipt respectively.
  Modules never grant noclip or bypass the framework's local-host authority.
- `NLVR.Debug.move` holds positions, play space, cumulative room distance, follow receipts,
  turn/error, physical/toggle crouch, command speed, vignette/fade, current target/refusal,
  last teleport/result and calibration/restart state, all as plain values.
- The module includes `cl_move_math.lua` in both realms; it is pure shared code under L's
  assigned prefix. Its helper/overlay files are deployed with the add-on by the existing packager.
- Tests use the required `vr_move` prefix, so run them explicitly with
  `python -m unittest discover -s companion/tests -p vr_move_tests.py -v`.
  Q can import `VRMoveTests` into the tools gate's discovery bridge during integration.

M's current page emits `height_calibrate`, which L handles. Its help needs to mention the restart
when `calibrated.restart` is true; a live native-scale setter remains an owner-level alternative.
V4 must preserve/rebase command movement if it replaces the final command's head aim with gun aim.

## Tests and evidence

Everything here is local, git-ignored, under this worktree's **`out/vr/v2l/`**.

- **42 LuaJIT scenarios pass.** They use the real modules and F's independent Euler/wire stand-ins,
  with an independent swept-AABB world. Numerical witnesses include 100 x 0.4-unit room steps =
  **40 units**, a **12-unit ordinary step**, a **48.25-unit mantle**, **0-unit landing/turn error**,
  **100/300-unit/s** authoritative flight and **64/28/82-unit** standing/duck/seated eye heights.
  Checks include stale/repeated/nonfinite/oversized input, tracking reacquisition, wall discard,
  climb arbitration, canceled queued teleport, changing obstacles, a 72-unit hull under a
  76-unit doorway, a head clear beyond a thin ceiling, and reverse teardown. Cumulative room
  distance continues beyond 20000 units using explicit float32 components; a paused teleport
  expires in wall time; blink stays opaque after the authoritative result before fading out.
- The original **80 VR page/framework scenarios pass** with their isolated camera contract.
  When collision queries are unavailable L leaves that camera consumer intact; the new harness
  supplies real collision/player interfaces and exercises active locomotion.
- Release gate 1 passes: **34/34 CTest**, Python **29 + 26 + 902 = 957**, **7 availability skips**.
  `release-1.log` is before N. Release gate 2 passes after N: **34/34 CTest**, Python
  **29 + 26 + 909 = 964**, **7 availability skips**, no failures (`release-2.log`).
  **Final gate PASS:** `tools/test.ps1 -Config Release`, `release-final-8.log`: **34/34 CTest**,
  **964 Python cases**, **7 availability skips**, **0 failures**, ending `All checks passed`.
  The separate **42/42** movement cases and current source hashes are in `offline-final.json`.
- `vr_move_session.py --case combined --seconds 85` drives actual native timeline input through
  production modules and the unchanged snapshot/session driver, retaining all eyes/depth/mirror
  and overlay canvases. It clears physical keyboard/mouse input only inside the private test mover.
  The task's capture checker still requires visible wrist glyphs and every standard capture file;
  it also decodes every extra canvas and checks black fades and coloured rings by their actual role.
  V1's assumption that every overlay contains white wrist text is unsuitable for a black vignette.
- `vr_move_check.py` separately checks actual distances/directions, crouch, jump, heights, flight,
  head/body alignment, turns, landings, server refusal, intermediate shifts and canvas pixels.
  Native counter success by itself is insufficient; missing/incorrect feature records fail.

### Retained diagnostic, not feature acceptance

`sim-combined-01`, package v2l.4, completes the standard native acceptance: **6918 rendered/matched
frames**, **0 submitted**, **0 unmatched**, **0 Submit errors**, **0 Lua errors**, SDK absent,
clean two-cycle teardown/settings restoration. The scripted 1 m walk is **39.9688 units**
(net vector quantization), turn pivot error **0**, flight **100/300 units/s**, crouch/seating and
height measurement work. A ledge mantle succeeds. The ordinary head-directed walk and blink/shift
correctly hit/refuse the spawn area's x=1024 wall, so this is **not** a complete feature pass.
Its semantic acceptance records those failures. The corrected fixture selects open ground by
standing-hull sweeps; the deliberate wall case uses that real BSP wall from x=984 and then resets
to open ground to check that blocked input cannot replay. No depot/geometry file is changed.

This diagnostic also proves the captures: motion vignette **1031 x 1033**, centre RGBA **0,0,0,0**,
border max alpha **92**; target **261 x 263**, **22178** green or red pixels at the relevant stages.
Raw captures and `L-capture-metrics.json` remain. Images were inspected. The eye image contains
path-traced world/ledge; the UI is separately captured, as SteamVR overlays must be.

It ran while the Release gate was active: its **81.54 rendered FPS** and **12.574 ms** GPU command
work, including **0.611 ms** eye warp and capture transfers, are contextual receipts, not tuning
claims. Simulation has no compositor frame rate. It restores **2877/2877 depot files**, with no
missing/size/hash mismatches, no protected-file changes, and all eleven preserved trees/files
identical (`restoration.json`, `cleanup.json`).

The first preparation (`index-movement-01`) refused my uppercase test chunk name **before game
launch**, then rolled back cleanly. Subsequent queued old-package attempts were stopped only
while waiting for somebody else's lock, before snapshots/PoC changes. They are not game tests.
Other tasks' locks and games were never removed or ended.

### Final acceptance

The selected package is **v2l.8**,
**2085467476 bytes**, SHA-256
`bea87f92678b54306dd5b87df30690692d3232e1127fd29cb3070a275617a041`.
It contains the accepted N module and L's level-route/collision/arbitration fixes, with the
existing packaged runtime. No L runtime/native import is needed.

**Final simulated acceptance PASS:** `sim-combined-06`, selected v2l.8, **36/36 semantic
checks**, **6803 rendered frames**, **6804 camera matches** (one in flight at the sample),
**0 submitted**, **0 unmatched**, **0 Submit errors**,
**0 Lua errors**, no SDK. Two native Start/Exit cycles, exact setting/live-selector restoration,
no remaining session hooks/timers/receivers/global, and clean **2877-file** depot verification.
See `summary.json`, `movement-acceptance.json`, `L-capture-metrics.json`, `restoration.json`
and `cleanup.json` in that run.

| Measured feature | Simulated result |
|---|---:|
| Scripted 1 m room walk | 40.0000 units (40 expected) |
| 2 s hand-directed walk | 410.876 units, +Y |
| 2 s head-directed walk | 410.873 units, +X |
| 1 s sprint | 414.212 units, +X |
| Head/hull horizontal error at milestones | 0 units |
| Snap / smooth / mouse turn | -30 / -120.849 / -2.200 degrees |
| Turn head-position error | 0 units |
| Standing / toggle-duck / seated eyes | 64 / 28 / 82 units |
| Physical crouch while toggle stays on | 28 units, both controls active |
| Jump rise | 31.627 units |
| Quarter / three-quarter trigger flight | 99.999974 / 299.999961 units/s |
| BSP wall room displacement | 23.9688 units, stopped at x=1007.9688 |
| Displacement after leaving the wall fixture | 0 units (no stored input) |
| Blink / shift / mantle / zero-vignette blink error | 0.027 / 0.020 / 0.03066 / 0.027 units |
| Intermediate shift receipts | 20 |
| Server refuses forged invalid destination | `slope`, request 60000 |

Walk/sprint totals include Source acceleration, stopping friction and the fixture's small ground
slope; acceptance allows 45 units around the 400-unit ideal. The measured vectors prove hand/head
direction. Physical crouch holds at **1.2 m** and releases at **1.3 m**; calibration measures
**1.600000024 m**, writes **39.9999994 units/m**, and keeps the active native/Lua scale **40**.

The final captures contain **22178 green/red target pixels** at their respective stages, vignette
centre alpha **0** and border alpha **92**, and full-fade centre **RGBA (0,0,0,255)** with the
optional vignette set to zero. Every capture retains eye/centre/depth/mirror/timings and the
individual overlay PNGs. UI stays out of the path-traced eye image by design.

Steady simulated throughput is **80.697 rendered FPS**, GPU command work **11.325 ms**, eye warp
**0.589 ms**, render-thread CPU **4.134 ms**. Captures/transfers are included; this is not a
compositor rate or a performance-tuning claim.

`sim-combined-03` (v2l.6) is another retained diagnostic: **6691 matched rendered frames**, no
native/Lua errors and clean restoration; all semantic items except a stale crouch-release debug
sample pass. It paired a new native pose with the prior PostRender state after a capture stall.
The final probe subscribes after L's own debug updater; `sim-combined-05` records the correct
1.2 m hold and 1.3 m release. No feature failure is suppressed in the retained checker output.

The prior v2l.7 control `sim-combined-05` also passes its **35/35 semantic checks**, **6730 matched
rendered frames**, no native/Lua errors and clean restoration. The v2l.8 timeline additionally
bends physically while virtual crouch stays on, proving 28-unit eyes without a height pop.

**Index acceptance PASS:** `index-combined-02`, the same selected v2l.8 package and 85-second
timeline, both shared locks: **36/36 semantic checks**, **3756 rendered/submitted/matched eye
pairs**, **0 Submit errors**, **0 unmatched poses**, **0 dropped compositor frames**, **0 Lua
errors**. SteamVR was already running, SDK ready, simulation false, **90 Hz**, **2468 x 2740**
per eye. Centre **3080 x 2752**, traced **1540 x 1376**, window **1280 x 720**, render scale **1**,
`mat_queue_mode 2`. Twelve complete capture sets include the eye/centre/depth/mirror/timings and
the owned overlays; green/red rings, opaque fade and the ledge/world eye image were inspected.

| Measured feature | Index result |
|---|---:|
| Scripted 1 m room walk | 39.9999 units |
| Hand / head walk, 2 s | 404.877 / 404.872 units, +Y / +X |
| Sprint, 1 s | 408.238 units |
| Snap / smooth / mouse turn | -30 / -117.442 / -2.200 degrees |
| Head/hull and turn-pivot error | 0 units |
| Standing / duck / combined-duck / seated eyes | 64 / 28 / 28 / 82 units |
| Jump rise | 31.760 units |
| Quarter / three-quarter trigger flight | 99.999997 / 299.999959 units/s |
| BSP-wall displacement / stored motion afterward | 23.9688 / 0 units |
| Blink / shift / mantle / zero-vignette blink error | 0.027 / 0.020 / 0.03066 / 0.027 units |

Steady accepted rate is **44.141 pairs/s** at 90 Hz; **52.740%** of compositor presents are
reprojected, with no drops. GPU commands/SDK **12.463 ms** (trace/volumetrics **6.708**, upscale
**2.423**, warp **0.627**, captures **1.457**, overlay transfers **0.151**); render-thread CPU
**3.930 ms**. Elapsed GPU span **22.166 ms** includes **9.703 ms** of queue gaps; it is distinct
from command work. These measurements include deliberate captures and are acceptance receipts,
not an Auto/performance tuning claim. The SDK's app metric is **11.678 ms**.

Both Start/Exit cycles restore every compared variable and live selector with **0 differences**;
the final inventory has only `PopulateToolMenu:nativeloader_vr`, **0 session timers/receivers**, no
`NLVR` global and no OpenVR DLL loaded after Exit. Server lifecycle logs retain the off-state
permanent stub. Rollback verifies **2877/2877 depot files**, **0** missing/size/hash mismatches,
all preserved originals identical, **0** protected-file hash changes. No field game was running
that needed ending; the authorised field-quit helper was not needed. SteamVR is left running.

Machine-checkable consolidation: **`out/vr/v2l/acceptance.json`**, checking both final summaries,
both 36-case semantic receipts, protected hashes, complete rollback/cleanup, Release, all 42
offline cases/current source hashes, and own commit identities/trailers.

## Scope and history

Claude merged N into `vr2` as **366897d**. L merged that direction into this branch as **b3db042**;
the only conflict combined the decision-index entries, retaining 0161 and L's 0165/0166.
N's accepted binary/provenance changes are inherited, not an L import. After N landed,
feature runs switched to simulation; no pre-N Index feature run was used.

Every own first-parent commit uses the configured SheepyLord identity and ends with the required
Codex trailer. Git initially retained conflict comments after the merge trailer; four local
commits were reparented with **identical file trees** to correct that message. The mapping and
tree identities are in `commit-trailer-repair.json`. N/main/vr2 history was untouched. Package/run
receipts naming the old local hashes still identify those same trees.

No field game needed ending. SteamVR was already running and is left running;
no setting, helper, registry option, launch option or user.conf was changed for VR. Tests touch
only the PoC through its standard backed-up transaction. Review/merge and milestone approval
remain Claude's and the user's work.
The seven superseded local GMAs were removed after verified restorations or before any game used
them: **14598157161 bytes** reclaimed. Their JSON inventories, digests, logs and all captured
evidence remain; only selected v2l.8 is retained (`superseded-package-cleanup.json`). Lock-only timeouts
created no PoC transaction and were retried without touching the other owners.

## Open/integration work

- Native world scale is latched at Start. Changed calibration persists the correct next-start
  height/scale and exposes `restart`; it does not silently make the Lua and stereo scales disagree.
  M/Q should show that notice or own a controlled restart/live native setter.
- Room translation deliberately incurs one local server tick. An unworn headset cannot establish
  human comfort, sickness tolerance, preferred vignette strength or physical reach calibration.
- Full combined H/M/P/R and V4 acceptance belongs to Q. This branch does not claim hand models,
  controller collision proxies, menu interaction, weapon aim or R's runtime artefact fixes.
- The existing runtime's phase-one warp, near-hand limits/ghost lines and performance presets
  remain R/V6/V7 work. No SteamVR setting was tuned to conceal a result.

## Reproduction

Use fresh evidence names. Python 3.12 via `py -3` has Pillow for unattended game screenshots;
the normal terminal Python runs the offline checker/gate. Both drivers wait for other task owners.

```powershell
python -m unittest discover -s companion/tests -p vr_move_tests.py -q
py -3 companion/tests/vr_move_session.py --case combined --simulate --package out/dist/gmod-rtx-remix-0.0.0-v2l.8.gma --evidence out/vr/v2l/next-sim --seconds 85
python companion/tests/vr_move_check.py out/vr/v2l/next-sim
py -3 companion/tests/vr_move_session.py --case combined --package out/dist/gmod-rtx-remix-0.0.0-v2l.8.gma --evidence out/vr/v2l/next-index --seconds 85
python companion/tests/vr_move_check.py out/vr/v2l/next-index
tools\test.ps1 -Config Release
```

## Text for Q's shared documents

- CHANGELOG: VR now follows room walking with the player's collision hull, supports mirrored
  hand/head stick locomotion, head-pivot turns, server-checked blink/shift and ledge mantles,
  physical/toggle crouch, trigger-speed noclip and overlay comfort/safety fades.
- COMPONENTS: L's move module owns locomotion, calibration and plain debug state; its pure maths
  helper is included by both realms; its canvas helper owns all locomotion UI. The server move
  module arbitrates below climbing and above ordinary movement without granting permissions.
- ROADMAP: task L's V2 movement/comfort passes 42 offline cases, 36 simulated and 36 Index feature
  checks, with 3756 matched/submitted pairs and the Release gate. Retain the native-scale restart
  and worn-comfort limits; review/integration and milestone approval remain separate.
- TESTING: add the 42 offline scenarios through the tools gate's import bridge, semantic PoC
  checker, corrected open-ground/BSP-wall fixture and separate simulated/Index counter receipts.
- RESEARCH: client predicted SetupMove/FinishMove do not run in single-player (Facepunch docs
  linked from ADR 0165); room follow therefore has server authority. Engine net.WriteVector
  quantization makes the measured 40-unit room walk 39.9688 units. The spawn-area x=1024 wall
  stops a 32-unit hull at x=1007.9688; it is unsuitable as the origin of a free +X distance test.
  The final cumulative room wire uses explicit float32 components to avoid that codec's precision
  and range limits. Add the final Index frame/GPU metrics and verified restoration counts above.

## Follow-up

Claude accepted L into vr2 as e01d344 and requested same-frame head translation plus zero command
roll. On resumption v2l fast-forwarded vr2 through 346bd53 before any implementation. Task S's
CreateMove/settings work remains untouched: the only core code change is the `feet()` accessor's
optional owned `ViewFeet(base)` resolver. No new ADR 0167 was made; the dated follow-up in
[0165](../decisions/0165-the-player-follows-the-vr-head.md#follow-up--2026-11-11-same-frame-head-translation)
records the changed latency decision.

### Measurement and result

Evidence: **out/vr/v2l/follow-up/**. `vr_move_latency_probe.lua` wraps the real owned CalcView
callback and records its actual return once per rendered engine frame, together with the same
frame's raw pose, sequence, tick, player feet and rolls. The horizontal reference is the initial
world camera plus tracking displacement at fixed yaw/scale, without room consumption. Gravity
and terrain height are excluded from horizontal error. Each run retains raw console records,
`latency-frames.csv` and `latency-analysis.json`. No resting milestone substitutes for this data.

The 22-second simulated timeline moves sideways at **0.5 m/s for 2 s**, then **1.5 m/s for 2 s**,
then **2 Hz +/-5 cm for 3 s**. Native interpolation samples its 50 Hz input at rendered-frame
times. It ends with **25 degrees of head roll**. Error/speed gives ramp lag; interpolation and
a 0.25 ms search give sway cross-correlation lag. Stable windows exclude transition boundaries.

| Quantity | Before, original mover | After, final predictor |
|---|---:|---:|
| Rendered CalcView rows | 1846 | 1938 |
| 0.5 m/s mean lag | 38.533 ms | -0.00348 ms (floating-point noise) |
| 0.5 m/s mean / p95 / max error | 0.77065 / 0.88940 / 1.15198 units | 0.000071 / 0.000122 / 0.000183 units |
| 1.5 m/s mean lag | 38.756 ms | -0.00359 ms (floating-point noise) |
| 1.5 m/s mean / p95 / max error | 2.32535 / 2.66510 / 3.14911 units | 0.000215 / 0.000305 / 0.000305 units |
| Sway correlation lag | 38.75 ms | 0.00 ms |
| Sway mean / p95 / max error | 0.64751 / 1.02258 / 1.10046 units | 0.000396 / 0.000793 / 0.000854 units |
| Slow maximum step-increment error | 0.49799 units | 0.000061 units |
| Fast maximum step-increment error | 1.32391 units | 0.000061 units |
| Sway maximum step-increment error | 0.33911 units | 0.000854 units |
| Head / camera roll | 25 / 25 degrees | 25 / 25 degrees |
| Command / player roll | 25 / 25 degrees | 0 / 0 degrees |

Before is **latency-before-02**, package `v2l.latency-before.1`; after is **latency-after-02**,
package `v2l.followup.2`. Both pass native acceptance and restoration. The corrected slow maximum
is **273 times below the 0.05-unit requirement**. There are no exact zero holds while tracking
moves in either measurement: Source interpolated its old tick updates, but with large uneven
increments. The corrected increments match the same-frame tracking increments within the bounds
above; a large step caused by a longer rendered frame is also present in that frame's reference,
rather than being labelled tick stepping. The after-Exit record independently gives **0-degree
player roll and 0-degree flat CalcView roll**.

### Approach and validation

The server remains the hull authority. After FinishMove it sends cumulative consumed/discarded
room intent, cumulative actual room displacement and the final feet origin, as float32 values.
The render predictor adds **only unprocessed room intent** to that final authoritative origin.
Normal stick/climb/teleport movement is already included in the origin and is never subtracted;
Source's current floor Z remains, adding only an unacknowledged room step. A client hull sweep
clamps the predicted displacement at walls, with the full fade plus the existing eye sweep.
Absolute receipts recover cleanly from changed-only coalescing and delays. No player entity is
moved on the client, and no movement permission/trust rule changes.

This was chosen over consuming the head into delayed feet: the measured free-space transform is
same-frame, rather than hoping a 66 Hz body arrives before an 80/90 Hz render. The resolver is
shared by camera, hands and tracking/world conversions, is owned by L and removed on Stop.
The default core path is unchanged when it is absent. L does not call Space.Shift in this path.
The command copies pitch/yaw with roll explicitly zero; camera tracking retains the head roll.

**46/46 offline cases pass**, including 180 rendered poses with differently timed/late body
receipts, prediction blocked at a wall, discarded input, retained stick/teleport/falling-floor
movement, real-core ViewFeet round trip/cleanup, and camera versus command roll. The original
**80/80 framework/page cases pass** too. Task S owns the gate bridge; no bridge was edited here.

**36/36 simulated regression checks pass** in **combined-sim-01** using the final package, with
**6752 rendered/matched frames**, no Lua/native errors and clean rollback. The single final Index
run appends the same latency/roll timeline after these 36 movement checks, for **105 seconds**,
below the three-minute limit.

**Final Index PASS**, `index-final`: **4663/4663 rendered/submitted/matched eye pairs**, **0**
Submit errors, unmatched poses, dropped compositor frames or Lua errors; **36/36** movement
checks. Its **955** measured CalcView rows give maximum errors **0.000122 / 0.000061 / 0.000244**
units for slow/fast/sway, **0.00 ms** sway correlation lag, and maximum increment errors
**0.000061 / 0.000061 / 0.000122** units. No tick-rate holds occur while tracking moves. The
camera follows the **25-degree** head roll while command/player/flat-after-Exit roll are **0**.
The SDK was ready, simulation false, Index **90 Hz**, **2468 x 2740** per eye. SteamVR was
already running and remains running. No field game needed ending.

All four selected runs (before/after measurements, simulated regression, final Index) restore
**2877/2877 depot files** each with no missing/size/hash mismatches, no protected-file changes,
clean cleanup, both Start/Exit cycles and exact archived/live-selector restoration. Logs, CSVs,
JSON records and captured images remain under the evidence root. Machine-checkable consolidation:
**`out/vr/v2l/follow-up/acceptance.json`**, `success=true`.

**Final gate PASS:** `tools/test.ps1 -Config Release`, **34/34 CTest entries**, Python
**29 + 26 + 909 = 964**, **7 existing availability skips**, **0 failures**, ending `All checks
passed` (`follow-up/release-final.log`). The separate **46/46** suite and current source hashes
are retained in `follow-up/offline-final.json`; task S's bridge is not on this task's base yet.

Selected local package: **0.0.0-v2l.followup.2**, **2085485737 bytes**, SHA-256
`97e251b3744c6a724012991e33c2fd0a83f125b62f91fbd4e1d9f14c2e57f517`.
No native/runtime binary input was imported. Calibration's next-Start limitation and human
comfort evaluation outside these measured translation/roll requirements remain as above.

Reproduce with a fresh evidence folder and the selected package:

```powershell
py -3 companion/tests/vr_move_session.py --case latency --simulate --package out/dist/gmod-rtx-remix-0.0.0-v2l.followup.2.gma --evidence out/vr/v2l/follow-up/next-latency --seconds 22
python companion/tests/vr_move_latency_check.py out/vr/v2l/follow-up/next-latency --require-fixed
py -3 companion/tests/vr_move_session.py --case followup --package out/dist/gmod-rtx-remix-0.0.0-v2l.followup.2.gma --evidence out/vr/v2l/follow-up/next-index --seconds 105
python companion/tests/vr_move_check.py out/vr/v2l/follow-up/next-index
python companion/tests/vr_move_latency_check.py out/vr/v2l/follow-up/next-index --require-fixed
```

Two diagnostic attempts are retained. The first baseline was refused **before VR Start** because
the pretty-printed 100 Hz timeline exceeded 1 MiB; a bounded 50 Hz timeline corrected that.
`latency-after-01` met timing/roll criteria but failed the last live frame-generation comparison.
Every first-cycle flat sample had restored FG=1; the second Exit comparison could run before its
first flat GPU frame and still expose VR's FG=0. The generated probe now waits 0.5 seconds after
native off, keeps the live comparison fatal, and changes no renderer settings. The selected
`latency-after-02` run has exact selector restoration, without that sampling failure.

Implementation commits: **043b3ba** (measurement), **9a65c92** (render prediction/core resolver/
receipts/zero command roll), **bdc6e6c** (separate collision from interpolated floor), **066d9ee**
(flat roll witness), **ddde6c6** (GPU-selector observation timing), **44b2693** (one combined
Index timeline). Every message uses the configured identity and requested Codex trailer.
No push, merge into main/vr2, publication, loader change or SteamVR setting change.

### Smooth locomotion between server ticks — 2026-11-11

Claude accepted the first follow-up into vr2 as **cd484e4**. L fast-forwarded that merge before
this check. This section records the additional non-room motion correction; prior results above
remain historical measurements of their selected packages.

All new evidence is under **out/vr/v2l/locomotion/**. `before` uses the accepted `v2l.followup.2`
package, with no production changes. The stationary-head timeline walks for **2 s**, sprints for
**1 s**, releases sprint, resets on open ground, then flies level for **2 s at full trigger**.
The client records every real CalcView result, LocalPlayer:GetPos, the original C.Feet and
GetNetworkOrigin. A private server hook independently records every FinishMove origin, velocity,
mode, tick, simulation time and same-process monotonic time. It adds no network traffic.

**Engine finding:** in single-player the original core base and `LocalPlayer():GetPos()` are
identical in these rows. They are interpolated, not tick held: they match the authoritative
piecewise-linear path at **client CurTime minus 0.015 s**, with **0.000037-unit RMS** error in
steady walking. That is one simulation tick of presentation delay; relative to the latest
already-executed server origin, their mean delay is **7.019 ms walking**, **7.062 ms sprint**
and **7.677 ms flight** (p95 approximately **14 ms**). GetNetworkOrigin is tick held. The former
FOLLOW-based walking/sprint camera matches that held origin; flight still followed the old engine
path. The severe zero-step regression was therefore new for walking/sprint, while flight's
lesser unevenness already existed in the engine interpolation.

| Steady interval | Previous camera | New camera (`after-01`) |
|---|---:|---:|
| Walking mean step | 2.2394 units | 2.2529 units |
| Walking p05 / p95 step | 0 / 3 units | 1.8665 / 2.6423 units |
| Walking zero-step holds | 36 / 142 intervals | 0 |
| Walking time-normalized step spread | 159.570% | 8.208% |
| Sprint mean step | 4.5600 units | 4.7226 units |
| Sprint p05 / p95 step | 0 / 6 units | 4.0869 / 5.4207 units |
| Sprint zero-step holds | 12 / 50 intervals | 0 |
| Sprint time-normalized step spread | 160.565% | 7.258% |
| Full-trigger flight mean step | 4.6309 units | 4.6273 units |
| Flight p05 / p95 step | 4.2322 / 5.1014 units | 4.0918 / 5.2992 units |
| Flight time-normalized step spread | 27.829% | 8.202% |
| Largest backwards step after sprint | 0 units | 0 units |

The spread is p95 minus p05 divided by the mean. Both raw increments and render intervals are
retained in `motion-frames.csv`/`motion-analysis.json`; time-normalized increments divide by their
actual render interval before comparison. This is necessary to distinguish tick judder from
real frame-time variation: baseline render intervals themselves have **36–38% raw spread**.
Raw position increments cannot legitimately be identical across unequal elapsed frame times.
No interval or zero hold is discarded. The new normalized spread meets **10%** for all three
steady speeds. New mean lag behind the latest server origin is **21.849 / 21.932 / 11.330 ms**
for walk/sprint/flight; this explicit motor buffering does not apply to physical head tracking.

**Approach:** FOLLOW now includes double simulation/wall timestamps and a discontinuity
generation. Subtracting cumulative actual room displacement from the final server origin gives
the non-room trajectory. The client linearly interpolates that trajectory one simulation tick
behind on a monotonic render wall clock mapped to uniform simulation ticks. Arrival time is not
the clock, nor is the jittery client game-clock phase. A monotonic cursor never moves backwards
and never extrapolates beyond the newest authoritative sample, so stopping cannot overshoot and
then correct backwards. Normal movement, pushes, platforms, gravity and shift steps share this
XYZ path; existing noclip uses it too. Blink/respawn/mode/large kinematic discontinuities advance
the persistent generation and reset history, including after coalescing. Identical idle states
do not send merely to advance timestamps. History is bounded to one second.

Current room displacement is added **outside** the delayed trajectory. The head therefore keeps
same-frame response, and the client hull/eye sweeps plus fade remain. `head-after` repeats the
unchanged 0.5/1.5 m/s and sway probes: maximum errors **0.000183 / 0.000366 / 0.000549 units**,
**0 ms sway lag**, no tick holds; command/player/flat roll stays **0**, camera roll **25 degrees**.

`combined-after` passes **36/36 simulated movement checks**, including wall fade/refusal, shift,
blink, mantle and restoration. Its old zero-separation assertion during active flight is now
correctly scoped to room-follow/wall samples: deliberate motor interpolation is permitted here.
Every camera/hull separation remains recorded by milestone; motor lag is checked by the separate
rendered-frame analysis, rather than silently hidden. **48/48 offline cases pass**, including
66-tick/90-render motion, no backwards sprint stop, room input added outside the motor buffer,
discontinuities and the actual eight-byte timestamp wire. No task S files/bridges were edited.

The final single Index run (`index-final`, `--case allmotion --seconds 127`) includes the 36
checks, the unchanged head probes and these locomotion intervals, below the three-minute cap.
**PASS:** **5618/5618 rendered/submitted/matched pairs**, **0** Submit errors, unmatched poses,
dropped compositor frames or Lua errors; **36/36** acceptance checks. Native SDK ready, simulated
false, Index **90 Hz**, **2468 x 2740** per eye, centre **3080 x 2752**, traced **1540 x 1376**.

| Index steady motion | Walking | Sprint | Full-trigger flight |
|---|---:|---:|---:|
| Mean step | 4.4422 units | 8.9216 units | 8.9402 units |
| Raw p05..p95 spread / mean | 9.283% | 16.754% | 17.308% |
| Raw standard deviation / mean | 4.859% | 5.663% | 7.476% |
| Time-normalized p05..p95 spread / mean | 5.998% | 7.942% | 5.645% |
| Zero-step holds | 0 | 0 | 0 |
| Mean lag behind latest server origin | 18.306 ms | 18.543 ms | 18.615 ms |

The largest backwards camera step after sprint release is **0 units**, under **0.1**. Raw
standard deviation is under 10% in each hardware interval; the normalized p05..p95 measure is
also under 10%. The wider raw sprint/flight quantile ranges are retained explicitly because
their rendered intervals vary too; no claim is made that raw frame-time jitter disappeared.
Steady accepted rate is **44.454 pairs/s**; **51.227%** reprojection, **0** drops. GPU commands/SDK
**12.271 ms**, warp **0.907 ms**, render-thread CPU **3.853 ms**, including deliberate captures.

Head translation remains same-frame on hardware: slow/fast/sway maximum error
**0.000183 / 0.000305 / 0.000366 units**, **0 ms** sway correlation lag and no tracking holds.
Camera roll stays **25 degrees**, command/player/flat-after-Exit roll **0 degrees**.

Every selected before/after/head/regression/Index run restores **2877/2877 depot files**, with no
missing/size/hash mismatches, protected-file changes or cleanup errors. Both native cycles and all
archived/live-selector comparisons pass. No field game needed ending; SteamVR was already running
and remains running. Receipt consolidation: **`out/vr/v2l/locomotion/acceptance.json`**, success=true.

**Gate PASS:** `tools/test.ps1 -Config Release`, **34/34 CTest**, Python
**29 + 26 + 909 = 964**, **7 existing availability skips**, **0 failures**, ending `All checks
passed` (`locomotion/release-final.log`). **48/48** movement cases and current source hashes are
in `locomotion/offline-final.json`; the original **80** framework/page cases also pass.

Selected package **0.0.0-v2l.motion.1**, **2085489084 bytes**, SHA-256
`803dd09248f9c80bf9693a7b467bde36a392264ba62fd008a40139cce634f71b`.
Commits: **674d223** (measurement), **0a54e03** (separate render-clock non-room interpolation),
**a980659** (complete single Index sequence and separate motor-delay/alignment assertions).
No push, merge into main/vr2, publication, loader/native/runtime import or SteamVR settings change.

```powershell
py -3 companion/tests/vr_move_session.py --case locomotion --simulate --package out/dist/gmod-rtx-remix-0.0.0-v2l.motion.1.gma --evidence out/vr/v2l/locomotion/next-motion --seconds 22
python companion/tests/vr_move_motion_check.py out/vr/v2l/locomotion/next-motion --require-smooth
py -3 companion/tests/vr_move_session.py --case allmotion --package out/dist/gmod-rtx-remix-0.0.0-v2l.motion.1.gma --evidence out/vr/v2l/locomotion/next-index --seconds 127
python companion/tests/vr_move_check.py out/vr/v2l/locomotion/next-index
python companion/tests/vr_move_latency_check.py out/vr/v2l/locomotion/next-index --require-fixed
python companion/tests/vr_move_motion_check.py out/vr/v2l/locomotion/next-index --require-smooth
```

Design records: [0165](../decisions/0165-the-player-follows-the-vr-head.md) and
[0166](../decisions/0166-vr-teleport-and-comfort.md).

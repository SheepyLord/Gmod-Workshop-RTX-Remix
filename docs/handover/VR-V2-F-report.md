# VR V2/V3 task F: the add-on framework

Implemented on `v2f`, starting from the assigned `vr2` base. The feature tasks can replace
their own stubs without changing either composition root. No push, merge, publication, GitHub
workflow, loader source change, native binary import or field-install write belongs to this task.
The branch uses the configured SheepyLord identity and the required Codex co-author trailer.

## What is built

| Interface | Result |
|---|---|
| 1: layout | Every listed file exists, with its script sidecar. Client modules are core, hud, hands, move, ui, interact; server modules are move and interact. The six feature stubs register empty Start/Stop descriptors. One additional shared `core/sh_modules.lua` removes duplicated resource/lifecycle machinery between realms. |
| 2: modules | Fixed order, reverse Stop, module-owned hooks (`nlvr.<name>`), timers, subscriptions, movers, resolvers, overlay destruction and cleanup callbacks. Failed hooks log once and stop their module; the next mover/resolver still runs. Failed Start unwinds through the page. Core/camera and overlay-paint failures retain V1's session failure behavior. |
| 3: client core | `NLVR` exists only while active. One native sample per engine frame across CreateMove/CalcView/PreRender; one accepted camera per sequence. V1's held camera, owned CalcView registry, predicted floor, proxy/child hiding and exact Think/NoDraw restoration survive. Play-space transforms, poses/raw poses, main/off aliases, rays, shown-hand resolvers, movers, one-tick aim, events and plain debug values are exposed. |
| 4: input | The full default table is data in `Input.Mapping`. Dominant hand mirrors all roles and the wrist attachment. Physical controls include edges, held seconds, taps, analogue axes, curls and optional splay. Claims are first-owner-wins per frame. Missing input releases controls. |
| 5: overlays | Fourteen reserved odd size pairs, exact V1 wrist size, duplicate/reservation checks, owned partial creation, invalidation-only painting, balanced scopes, placement/visibility/alpha and world-ray hit tests. V1's unchanged HUD repaints only until runtime-copy acknowledgement. |
| 6: network | One channel/type byte, explicit module ranges, 1467-bit sync, client once per tick, wrap-aware sequence validation, finite/range/reach/rate/length checks. Module readers are scoped; bounded writer snapshots permit changed-only, coalesced, fair server output at most once per player/tick. |
| 7: server | The dormant companion stub has one string and receiver, no include or hooks. Only single-player/local listen host activates it. Per-player poses/history, lifecycle events, SetupMove arbitration and Move suppression are owned by the core. Death keeps VR running; last Stop/disconnect/shutdown removes the server core and all its hooks. |
| 10: settings | All fifteen archived variables live in one page block with help/ranges. The core reads at Start, installs callbacks only while active and removes them at Exit. No page layout or translated phrase changes. |

The two design records are [0159](../decisions/0159-the-vr-addons-framework.md) and
[0160](../decisions/0160-the-servers-vr-switch-and-local-host.md).

## Conventions the feature tasks need

The helper signatures in the plan are unchanged. These unspecified units and lifetime details are now explicit:

- `Space.Turn(degrees)` preserves the tracked head's world position. `Space.Shift(delta)` takes **world game
  units**, after L moves the player's feet by that displacement; call it once. It compensates anchor and the
  cached floor, preserving the head. The core initializes/recentres the space as V1 did; subsequent locomotion
  ownership is L's. Seated offset translates head and hands together so their relative geometry stays intact.
- Linear velocity is game units/s. Angular velocity is Source XYZ radians/s, matching native input. Head and
  hand `.raw` records remain tracking metres. A native controller's OpenVR -Z axis already becomes Source +X,
  so `Ray` uses its world angle's Forward for Index, Touch and Vive rather than applying a second model rotation.
- `ctx.resolver(priority, fn(hand,state))` runs in ascending priority: H before P. Set `state.shown`, `blocked`,
  `held` and `grip_curls`; leave `state.target` alone. `NLVR.Ray` follows the target controller, not its blocked hand.
- Client and server movers use ascending priority, stable on ties. Server movers run once for each SetupMove
  invocation; first true handles its matching Move. Change move data, not player entity position. Reserve lower
  numbers for climbing than teleport than noclip than ordinary walking.
- `NLVR.Aim(angles,owner)` lasts the current engine tick; the first owner wins. V4 should request it from a mover.
- Use `ctx.On(name,fn)` or `NLVR.On`/`NLVR_SV.On` from a module-owned callback. Server event names are `OnStart`,
  `OnStop`, `OnSync`, `OnDeath`, `OnSpawn`; convenience registration functions of those names also exist.
- Module Send writers receive a **net-shaped argument**: `function(w) w.WriteVector(pos) end`. Readers use the
  matching `net.ReadVector()`. Do not write to global net inside a Send writer. This lets the framework snapshot,
  compare and defer payloads without replacing global net functions. The conservative limit is 4096 bytes.
- `NLVR_SV.REACH` is 100 game units at the default 40 units/metre. `NLVR_SV.Reach(ply)` scales it for that player.
  `Players[ply].history[hand]` contains `{time, pose, seq}` entries for the last second. Invalid tracking is sent
  even after a valid sample; one second without sync clears pose validity and ages history out. Head/hands are
  replaceable tracking snapshots; P should keep persistent physics state under its own field on the player state.
  Modules must tolerate waiting for the first valid Frame/Pose after Start.
- Use the reserved key when requesting a reserved overlay size. `paint(object,width,height)` is already inside
  a target/2D scope. `Hit` takes world rays and returns UV and game-unit distance. Overlay attachment coordinates
  are tracking metres; front is -Forward, right is Right, up is Up. Source keeps named RT storage until game exit.
- `nl_vr_height` has the contiguous engine range 0..2.2; the core normalizes positive values below 1.2 to 1.2,
  implementing the plan's disjoint range without rewriting the player's archived value. Scale/calibration logic
  belongs to L; reading the setting alone does not change runtime world scale.

Example replacement for an existing client stub:

```lua
local module = {name = "move", order = 30}
function module.Start(ctx)
    ctx.mover(100, function(cmd)
        local input = ctx.Input
        local owner = input.Owner("off", "stick")
        if not owner or owner == ctx.name then
            cmd:SetForwardMove(input.off.stick.y * 150)
            cmd:SetSideMove(input.off.stick.x * 150)
        end
    end)
    ctx.On("teleport", function() ctx.Debug.move = {teleported = true} end)
end
function module.Stop() end
return module
```

Register entity removal and other resources with `ctx.cleanup(function() ... end)`. Modules should keep Stop
idempotent and safe after partial Start. They must add hooks through `ctx.hook`; the framework does not sweep
unrelated hooks or intercept global hook/net/VGUI functions.

## Tests and evidence

Evidence root in this worktree: `out/vr/v2f/`. It is local, git-ignored evidence; binaries/packages are not committed.

- Offline page/add-on/guard/catalog: **80 tests pass**, including the original 58 and twenty-two framework scenarios.
  The wire stand-in writes actual bits and IEEE754 float bytes; the transform stand-in uses full Euler maths.
  The framework tests cover round trips/turn/shift, poses/resolvers, mirrored mapping/edges/claims/taps/holds,
  settings, one-tick aim, failed hooks/movers and reverse cleanup, odd sizes/invalidation/attached hit tests,
  wire length/round trip/truncation, every validation category, server histories/rates/authority/events/movers,
  deferred changed-only payloads/fairness, stale tracking and client once-per-tick sync.
- Session-driver tests: **21 pass**, including moved-hook and both-realm probe inventories. The existing V1
  driver and probe still work; the probe now reads `NLVR.Debug`, all settings, and server lifecycle
  records. The optional older stand-in PoC driver embeds nested includes instead of loading stale deployed Lua.
- First full Release gate: one test-inventory failure, retained in `release-1.log`. The new server stub was
  absent from the test's explicit ordinary-policy names. The isolated 25-case render-guard suite passes after
  the correction. The production guard and exemption list were never changed.
- The corrected 90-second host acceptance (`index-02`, package v2f.4) passes: 4035/4035 matched eye pairs, zero
  Submit errors, zero unmatched poses, zero dropped compositor frames, five full capture sets, zero Lua errors,
  both Start/Exit cycles clean. Steady accepted rate is 45.0006 FPS at 90 Hz; command/SDK GPU work is 11.3089 ms.
  Flat phase mean is 8.7732 ms before and 8.7297 ms after VR. Server lifecycle inventories show 7 active hooks
  and 0 after Exit, one permanent receiver, 5997 accepted syncs/33 rejected in the first cycle, 79/12 in the second.
  Those sync rejections are separate from compositor errors; the protocol deliberately drops excess arrivals.
- The V1 baseline flat control (`flat-v1`, 30 seconds) passes: 3382 measured frames, 8.8722 ms mean / 112.7116 FPS.
  A direct, read-only server console query records active=false, hooks=0, receiver=false.
- Final package acceptance (`index-04`, package v2f.6, single-player, 60 seconds) passes: **2685/2685 eye pairs**,
  zero Submit errors, unmatched poses, dropped compositor frames or Lua errors; all five capture sets complete.
  Steady accepted rate is **44.7785 FPS** at 90 Hz, at the Index's **2468 x 2740 per eye**; centre **3080 x 2752**,
  traced **1540 x 1376**, window 1280 x 720, scale 1, `mat_queue_mode 2`. The short sampled interval includes the
  image transfers: GPU commands/SDK **12.4087 ms**, eye warp **0.7383 ms**, render-thread CPU **4.6071 ms**.
  These are reference receipts, not a performance-tuning claim. Initial GPU/process context is saved per run.
- Final server cycles (`index-04`) accept **3999** and **96** syncs, rejecting **37** and **20** excess/invalid
  arrivals respectively. An active supplementary sample in `index-03` identifies its 18 drops as `rate` only.
  Server topology is **7 hooks active / 0 off**, with the one permanent receiver. A separately injected read-only
  console query after final Exit independently records `{active=false,hooks=0,receiver=true}` in `index-04`.
  Exact query, owning lock token/PID and result are retained in `index-04-off-server-probe.json` and the console log.
- The final client inventory is only `PopulateToolMenu:nativeloader_vr`: **0 session hooks, 0 timers, 0 client
  receivers, no NLVR global**. All **30** compared game/VR variable strings and the live upscaler/FG selectors
  restore with **0 differences**. `openvr_api.dll` is absent after Exit. Two Start/Exit cycles pass in each run.
- The new flat control (`flat-f`, package v2f.5, 30 seconds) passes: **3579** measured frames, **8.3833 ms mean /
  119.2851 FPS**, against V1's **8.8722 ms / 112.7116 FPS**. No regression is measured in this one paired control;
  the 0.4889 ms difference is not claimed as a speedup. v2f.6 changes only the active wrist/overlay paint path;
  those files are not loaded while off. The flat run has no VR session hooks/timers/receiver/global and no SDK.
- The intermediate final-teardown control (`index-03`, package v2f.5, SP, 60 seconds) also passes: **2707 pairs**,
  no errors/unmatched/dropped frames and clean two-cycle teardown. Its image revealed the alpha regression below.
- **All six PoC runs, including excluded index-01, restore cleanly**: 2877 depot files verified on each rollback,
  no missing/size/hash mismatches, protected `user.conf` hashes unchanged, shared settings restored before normal
  quit. `restoration.json`, `snapshot/rollback.json` and `cleanup.json` retain the receipts; generated bulk copies
  were removed by the driver only after verification. Other tasks' lock owners were waited out, never removed.
- Machine-checkable consolidation: **out/vr/v2f/acceptance.json**. It checks five successful summaries,
  zero unexpected Lua errors, exact client inventory, server transition inventories, complete captures with visible
  glyph pixels, every protected-file/depot receipt and the final wrist RGBA. Raw data stays beside it.
- **Final Release gate PASS**: `tools\test.ps1 -Config Release`, log **out/vr/v2f/release-final.log** and
  **release-receipt.json**: **34/34 CTest entries**, Python **29 + 26 + 902 = 957 tests**, **7 availability skips**,
  **0 failures**, ending **All checks passed**. CTest took **47.38 s**, the main Python group **148.465 s**.
  Implementation is commit **62426ce**; subsequent edits only complete documentation/evidence.

The first Index run (`index-01`, package v2f.3) is excluded: its diagnostic tried `lua_run` from client Lua, which
GMod blocks, producing three Lua errors. Native pictures/submission and rollback worked, but the driver correctly
failed acceptance. The corrected probe makes no such request. Server lifecycle logs read the actual registry
and counters once at transitions. Supplementary realm snapshots use the existing external console driver, the
ordinary admin console path used to set up these tests, with the owning PoC PID/lock checked. No blocked-command
flag or engine protection is altered. That first Start initialized SteamVR, which had been closed; it remains
running throughout the subsequent controls.

## Scope exception and implementation history

`807c938` builds the framework; `d6c2142` fixes stale samples and failure during arbitration; `4cc429e` exposes
reach in game units and fixes the required inventory maintenance. `4ee1f6a` corrects the real-game probe;
`0fca583` completes teardown on a closing game channel; `62426ce` restores the exact V1 wrist clear RGBA. Every commit has the required identity/trailer.

The only exception to F's assigned file list is the one ordinary-policy filename in
`tools/tests/test_render_guard_addons.py` and its required sidecar update. The Release gate proved this was needed
by the explicitly assigned new companion server stub. The alternative would have incorrectly granted a new
production rendering exemption or left the required gate failing. This change preserves the existing assertion
that ordinary VR code gains no guard exemption. No other task's implementation files are changed.

The V1 regression capture also found a real alpha difference after the refactor: drawing a translucent
background rectangle produced `(11,17,24,217)` rather than V1's `(12,18,26,235)`. The final manager accepts an
optional clear RGBA and clears the wrist directly before 2D, as V1 did. The wrist test asserts those clear values.
This is the only extra overlay option; default canvases still clear to transparent black.

## Open and integration work

- H, L, M and P are deliberately stubs. Their features and the combined V2/V3/V4 acceptance belong to those tasks
  and Q. Nothing here claims completed hand rendering, locomotion, UI interaction or server physics.
- N's simulated-session API is not on this task base; this task's offline tests do not initialize OpenVR, and
  the required acceptance uses the real Index. Integrate the simulated mode before feature PoC runs.
- The page's look, options and translations remain M's. Native/runtime work, ghost-line reduction, true stereo,
  4K performance, height-calibration/runtime scale coordination and worn comfort are not solved by F.
- No trust allowlist, path rule or off switch is relaxed. Remote clients remain excluded; V5 owns multiplayer.
- Review and merge into `vr2`, then milestone approval, remain with Claude and the user.

## Text for Q's shared documents

- CHANGELOG: V2/V3 now has a dormant, local-host VR framework: modular client/server lifecycle, mirrored logical
  input with claims, owned overlay canvases, validated per-tick tracking and server movement arbitration.
- COMPONENTS: `vr/addon/lua/nlvr/client.lua` and `server.lua` compose fixed modules; `core/` owns session, input,
  overlays, networking and resource cleanup; `modules/cl_hud.lua` keeps V1's wrist; feature stubs are separate.
  The companion's server autorun is the off-state switch. The shared registry has no side effects on include.
- ROADMAP: F is implemented and tested on `v2f`; follow-on feature tasks replace their assigned stubs after review.
- TESTING: retain V1 regressions, add twenty-two framework scenarios and both-realm PoC inventories; real-package
  Index captures and flat controls accompany the Release gate. Only the permanent server receiver remains off.
- RESEARCH: Source-basis controller rays are +X after native conversion; OpenVR overlay front is Source -X,
  image right -Y and up +Z (`vr/native/pose_math.cpp`, `session.cpp`). The sync is 1467 bits including its type,
  at most one client packet/tick; accepted sample history is bounded to one second/1024 entries per hand.
  Facepunch's [net extension source](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/includes/extensions/net.lua)
  documents the receiver table/removal and excludes its 16-bit channel header from receiver length;
  [Game Movement](https://wiki.facepunch.com/gmod/Game_Movement) documents SetupMove/Move and move-data ownership.
  Add the hardware measurements and verified rollback counts above to the shared research notes.

## Final package and reproduction

The selected local package is **out/dist/gmod-rtx-remix-0.0.0-v2f.6.gma**, **1791 files / 2085381033 bytes**, SHA-256
`33854c23c3831f701776d71555d80fa1a20ceb71cbfb5e488f1549e1a03a94e0`. It was built from implementation
commit **62426ce**, checked with this worktree's `nlctl.exe`; no native binary or package input was imported.
Its content digest is `56188b8ca5d95d577b573e7604688de81fb629f449c497614dc2fe61115ac3c2`.
Its build JSON and `out/vr/v2f/package-6.log` retain the file count/digest and command. Subsequent edits are docs only.

```powershell
python -m unittest discover -s companion/tests -p test_vr.py -q
python -m unittest discover -s tools/tests -p test_vr_session.py -q
python tools/build_package.py --version 0.0.0-v2f.6 --require-nlctl --json
py -3 tools/vr_session.py --package out/dist/gmod-rtx-remix-0.0.0-v2f.6.gma --evidence out/vr/v2f/next-index --seconds 60
py -3 tools/vr_session.py --package out/dist/gmod-rtx-remix-0.0.0-v2f.6.gma --evidence out/vr/v2f/next-flat --flat --seconds 30
tools\test.ps1 -Config Release
```

The unattended game driver needs Pillow; these runs used the installed Python 3.12 via `py -3`. The normal
Miniconda terminal Python, which has no Pillow, ran the package build, offline tests and Release gate. Its
unattended-driver preflight remains covered; no package was installed into either Python. Every game used the
shared lock protocol and a fresh evidence folder. No field/legacy install, Steam setting/registry/launch option
or Remix `user.conf` was changed. SteamVR started normally through the first test's Start VR and was left running.

The final canvas is visually checked with its eye and mirror captures: **769 x 257**, background exactly
**(12,18,26,235)**, health **87**, armour **31**, ammo **18/256**; the changed canvas follows **63 / 47 / 9/54**.
The desktop marker/HUD stays on the mirror, outside the eye image. The three successful Index runs retain fifteen
complete eye/depth/overlay/mirror capture sets. They use the old runtime unchanged, so phase-one disocclusions and
near-hand limits remain R's work.

Only v2f.5 (the paired flat/control build) and selected v2f.6 packages are retained; the four superseded local
GMAs were removed after verified restorations. Their JSON inventories and build logs remain, with byte counts
in out/vr/v2f/local-package-cleanup.json. No task lock was removed except by its own driver. Other tasks may
be using the PoC after this handover; their sessions were never ended by this work.

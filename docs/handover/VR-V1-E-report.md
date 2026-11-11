# VR-V1-E report: page/add-on and Claude review follow-up

Implemented on **vr-e**, with the review follow-up based on c0a8e15. No push, merge, Workshop publication,
GitHub workflow, packaging import, loader change or render-guard change. Native/headset integration belongs to
VR-Q. This report supersedes the first pass's engine-setting restoration and broad 2D-suppression claims:
the review was correct that the old stand-in accepted an engine setter which real GMod rejects.

Main-checkout evidence: **out/vr/e/review/**,
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\e\review`.
The earlier translated-page UI evidence remains in main `out/vr/e/poc/`; worktree scratch is its own `out/vr/e/`.

## What changed after review

1. **No engine convar writes.** Removed the fps_max, cl_drawhud and r_drawviewmodel mutations completely. The
   first is Lua-blocked; the other two are unnecessary for this design. The offline engine-variable stand-ins
   now reject SetString, matching the native API. No attempt is made to bypass the blocked-command list.
2. **No global hook or VGUI replacement.** Removed replacements of hook.Call, hook.Run and vgui.Create, and all
   2D HUD/notice suppression. Ordinary PreDrawViewModel/PreDrawPlayerHands hooks return true;
   ShouldDrawLocalPlayer returns false. The fixes' body and weapon proxies and their render children are hidden.
3. **One authoritative camera.** While VR runs, only the CalcView event table is owned by the session; competing
   view hooks are held and later registrations/removals are preserved for restoration. The first camera per
   sequence is cached and pushed once. Its floor anchor is the supplied CalcView origin minus the player's
   GetCurrentViewOffset(), rather than GetPos().
4. **Real-game stand-in proof.** Added test-only vr_standin.lua, vr_poc.lua and vr_poc.py under companion/tests.
   They run the shipping page/add-on in GMod without loading the native VR module, record every API call,
   exercise manual Exit, an Events quit and genuine game ShutDown, export the wrist PNG and complete inventories,
   and compare returned/rendered camera positions with independent arithmetic.

Review implementation commits: **9c31f2a**, **f2e6d56**, **0aef9bf**, **e464369**, **1b088b4**, **8c049fc** (plus the
final documentation/result commits). Every commit uses the configured SheepyLord identity and the plan's Codex
co-author trailer.

## Engine convars: native evidence in both realms

The client API results are identical in single-player and on a listen host (`+maxplayers 2`):

| Variable | ConVar:SetString | Client RunConsoleCommand | Probe restoration |
|---|---|---|---|
| fps_max | rejected; 60.000 stays 60.000 | requested 61 is blocked; stays 60.000 | no mutation to restore |
| cl_drawhud | rejected; 1 stays 1 | 1 -> 0 actually changes | 0 -> 1 actually restores |
| r_drawviewmodel | rejected; 1 stays 1 | 1 -> 0 actually changes | 0 -> 1 actually restores |

Each rejected setter returns an error containing `attempted to modify ConVar not created by Lua`. The
[setter documentation](https://wiki.facepunch.com/gmod/ConVar:SetString) restricts it to Lua-created variables.
The [blocked-command list](https://wiki.facepunch.com/gmod/Blocked_ConCommands) includes fps_max; neither of the
other two appears in it. The list applies to the normal Lua command APIs, including Player:ConCommand; no
alternate route was used to force fps_max. The normal physical console/launch command line can set it. The
[RunConsoleCommand documentation](https://wiki.facepunch.com/gmod/Global.RunConsoleCommand) describes the local
client/listen-host behavior that the probe verifies here.

The probe changes the allowed two variables back **before Start**. The production addon subsequently leaves
all three alone throughout Start, Exit, simulated SteamVR quit and ShutDown. Every cleanup snapshot checks their
real strings. fps_max stays 60.000 in the live VR fixture; both draw variables stay 1, even though the 3D models
are hidden by hooks. Before quitting, poc_session.py legitimately restores the user's shared field config;
therefore the genuine ShutDown checks compare values immediately before/after addon cleanup (the restored cap
is 300, and remains 300), not the earlier launch fixture. This is recorded in the shutdown snapshot's before/fixture/now
fields and the test-only Stop wrapper. No engine flag, allowlist or protection was changed.

The deliberately blocked command emits one error in SP. A listen host logs the same client error twice,
including its server forwarding copy. The runner accepts exactly those messages and rejects other Lua errors:
**1 expected diagnostic in SP, 2 copies in the host run, 0 unexpected Lua errors in either**.

## What reaches the eyes and the proxy fix

The runtime's VR centre/eye images are taken before the game's subsequent desktop 2D passes. HUDPaint, the
default HUD, notices, menus and console remain on the game window over the mirror. They are not hidden by Lua.
The guard and lag report's global dispatch functions are untouched. The real-game HUDPaint witness runs
**775 times in SP and 846 on the host** while VR owns the view.

No ordinary post-centre orthographic 2D draw that enters the eyes was identified in this task. Perspective/world
3D2D cards are geometry, however: ARC9 gun/screens/scope paths are examples already discussed in
[ADR 0136](../decisions/0136-arc9-scopes-path-traced.md), and raster canvases have their separate path in
[ADR 0122](../decisions/0122-raster-canvases-keep-their-native-draws.md). VR-Q must check native saved eye images
for remaining installed add-on geometry; a desktop screenshot is not that proof.

The first real-game run found that SetNoDraw on the scripted weapon proxy alone was insufficient: its Think
calls the active weapon's DrawWorldModel and re-shows a separate ClientsideModel child. The current code pauses
**only the two render-proxy roots' Think methods** during the session, keeps their next think scheduled, and hides
their descendants too. Stop restores the exact prior raw Think fields (including nil) and NoDraw flags. A later
foreign Think replacement is not overwritten. No entity class, global metatable or proxy convar is changed;
normal player movement is unaffected. Reading the GPL fixes supplied these behavioral facts; their code was not
copied into this original MIT implementation.

The final captures show the pistol/view-model gone and returning at Exit. The direct draw witnesses record
**0 PostDrawViewModel and 0 PostDrawPlayerHands calls while VR owns the view**, in both modes. Before Start those
counts are 428/420; after manual Stop they resume for 178/176 frames (SP/host). The baseline, active and cleanup
inventories include the two roots plus their real C_BaseFlex child: hidden during VR, original flags and Think
function identities restored at manual Stop, quit and actual shutdown.

## Camera ownership, prediction and engine ordering

An ordinary CalcView hook cannot win reliably because GMod iterates hooks without an ordering guarantee. The
addon temporarily owns **hook.GetTable().CalcView**, not hook.Call/Run/Add or the gamemode. Its engine-visible
table has one VR entry; a metatable diverts late Add/Remove operations into the held original table. Stop restores
that original table identity and the preserved edits. A wholesale hook-library/event-table replacement is detected
and stops the session. The assumption is GMod's normal table-based dispatcher, as used by the package's guard.

The probe installs an existing competing camera and a later one. Neither is called during VR: **0 foreign camera
calls**. Their registrations and removals survive correctly. Every accepted view is cached by frame sequence;
an explicit second request with a wildly different origin returns that same view and makes **0 additional pushes**.
The real runs made **1621 such repeated checks**, alongside the natural engine queries.

The tracking floor is **CalcView origin - GetCurrentViewOffset()**. This uses the engine-provided predicted/
interpolated camera position and removes the actual eye offset once. The
[current-offset API](https://wiki.facepunch.com/gmod/Player:GetCurrentViewOffset) accounts for transitions between
standing and ducking; GetViewOffset() alone is only the standing value. First-head yaw is aligned to the supplied
camera angles. World scale is latched at Start (40 units/m; 72 units corresponds to 1.8 m) and matches the scale
sent to the runtime. A slider change while starting applies next session, not halfway through a frame.

The real tests moved the player **92.091081 / 92.091386 game units**. In these straight walking samples the
render-origin-derived floor and GetPos matched (maximum difference **0** in each mode), so no natural GetPos jitter
is claimed from them. The canonical supplied view remains the correct anchor; an offline test with a deliberate
(7,8,9) difference proves the implementation uses it rather than silently substituting GetPos. A duck-offset
transition is covered offline too.

Real GMod asks its main **CalcView before PreRender**. The PreRender-only first version sampled a pose one engine
frame old; the intermediate r2 trace records pose age 1 and a maximum view mismatch of 18 units. The implementation
now calls BeginFrame once per engine FrameNumber at the first CalcView or PreRender, sharing it with the later
callback. Additional camera queries do not wait or fetch another pose. This is an evidence-driven correction of
the work plan's assumed callback ordering; the nlvr/rtxvr interfaces and the user's architectural decisions are
unchanged. The final traces have **pose age 0 and rendered-view error 0**. Lost tracking still holds the last valid
head, and an absent pose is not pushed. The 140-degree culling FOV remains adjustable pending native S6.

| Final real-game measurement | Single-player | Listen host |
|---|---:|---:|
| SetFrameCamera calls | 775 | 846 |
| Independently checked camera error, maximum game units | 0.000031457 | 0.000007629 |
| render.GetViewSetup position error | 0 | 0 |
| Pose age in engine frames | 0 | 0 |
| Duplicate pushes / competing camera calls | 0 / 0 | 0 / 0 |
| Repeated camera checks | 775 | 846 |
| View-model / hand draws during VR | 0 / 0 | 0 / 0 |
| Desktop HUDPaint calls during VR | 775 | 846 |

## Wrist canvas and cleanup evidence

Both runs export the **real 769x257 PNG**, not a stand-in image. Each reads **health 87, armour 31, pistol 18/256**,
matching the game's desktop HUD at capture time. The fixture requested 12/36 before selection; at capture, after
selection, the game reports 18/256. The test uses those live values instead of substituting the fixture numbers.

The complete live render guard records **one allocation, 790532 colour bytes** for lua/nlvr/client.lua and
**0 refusals attributed to nlvr**. OverlaySource receives the same 769x257 dimensions. Three Start/Stop cycles reuse
that bounded Source target; the mock overlay registry is empty after shutdown. The generated PNG is 13,747 bytes
in each final mode. Runtime/compositor copies of that canvas still belong to native S8/VR-Q.

There are **14 game-window screenshots and 2 wrist PNGs** in:

- `review/poc/review-r3-standin-sp/`
- `review/poc/review-r3-standin-host/`

Each has flat-before, neutral head, head look while moving, head lean, flat-after-stop, flat-after-quit and
active-before-shutdown screenshots. `result.json` contains every mock API call, camera samples, hook inventories,
proxy flags/Think identities, engine-variable probes and all three exits. `summary.json` is the compact result;
`before-shutdown.json` retains evidence before normal quit. All exports travel through chunked console base64
into repo out/, with no test-evidence writes to the game's DATA directory.

The snapshots list **0 addon hooks and 0 session timers** after manual Stop, the Events quit and genuine ShutDown;
all **7 session hooks** are removed. CalcView's original table identity is restored. The global hook, VGUI and
require function identities remain unchanged, including during VR. Timer inspection uses the available native
table or the known session timer's Exists check; the addon itself creates no timers. The test-only instrumentation
is separate and ends with the test process.

The native VR module and OpenVR DLL are absent from both final runs' loaded-module lists. No VR lock was needed,
and SteamVR was not initialized, started/stopped or reconfigured. The PoC lock was taken exclusively and released
after rollback. No field/RTX_c install write, Steam registry/setting/launch-option change or depot modification.

`review/review-r3-snapshot/rollback.json`: **clean=true**, **2877 depot files verified**, no missing/size/hash
mismatches or registry differences. `review/review-r3-rollback-summary.json` records matching before/after hashes
for PoC user.conf and config.cfg. The field config is read only by the standard driver to restore shared settings.

## Reproduction, tests and retained history

```
python companion/tests/vr_poc.py --tag next-review
python companion/tests/vr_poc.py --tag review-r3 --evaluate-only
python -m unittest discover -s companion/tests -p test_vr.py -v
tools\test.ps1 -Config Release
```

The driver uses poc_session.py --lua for SP/maxplayers 1 and a listen host/maxplayers 2, with snapshots, -multirun,
-insecure and only the existing local package. It records source hashes in `review-r3-sources.json`, restores shared
settings before normal quit, verifies rollback and releases only its own lock. Test code is under companion/tests
and is not collected into the companion or VR package. The private include/require environment supplies only the
API stand-in; no global loader replacement or actual native module call occurs.

The live r3 runner originally classified the host's second copy of the deliberately blocked fps_max message as
unexpected. Its raw logs remain unchanged. The classification-only fix now requires exactly 1 SP/2 host copies;
`--evaluate-only` validates both saved game results and rollback with exit 0. This required no replay of unchanged
game code. `review/evaluation.log` and `review/review-r3-summary.json` record that successful evaluation.

Earlier r1/r2 runs remain as development evidence: r1 exposed proxy-child/direct Think drawing and an incorrect
shutdown fixture comparison after the driver's legitimate config restore; r2 exposed the one-frame-old pose.
They are not counted as the final acceptance runs. The prior page-only c0a8e15 evidence at 1080p/4K in English and
Japanese remains valid for the unchanged page/catalogs (44 new messages x 6 languages, 264 translations, complete
576-entry catalogs; machine translations awaiting human review). It did not prove the old addon behavior.

Offline **43 tests pass**: 42 LuaJIT cases/checks of real production Lua (including the complete guard canvas seam),
plus the catalog byte case. Coverage includes rejected engine setters, preserved 2D/VGUI/global functions,
exclusive/late CalcView registrations, the real callback order, sequence caching, predicted/duck offsets, proxy
children/Think restoration, partial failures, quit/shutdown, wrist repainting and dormant state. The page still
has no native load/addon include before an explicit request, no idle session timer/frame hook, and no status-file
reads when its cached page's parent is hidden.

**Final Release gate PASS:** `tools\test.ps1 -Config Release` on stable implementation/documentation commit
**a8bbfea**: **30/30 CTests**, Python groups **29 + 26 + 830 = 885 tests**, **7 skipped**, no failures, ending
**All checks passed**. The main Python group took 120.884 s. The final normalized log is
main `out/vr/e/review/release-test.log` (raw worktree log: `out/vr/e/review-release-stable.log`).
Only this report's final results were filled after that run; production code and tests were unchanged.

All generated evidence and scratch remain under repo out/. Snapshot copies remain retained; the previous round's
automatic approval review blocked their cleanup with "blocked by policy". No attempt was made to circumvent that
restriction. The conventional test wiring remains the discovery adapter under tools/tests and the strict guard
inventory's ordinary-page entry; production guard policy is unchanged.

## Exact Info fields read by the page (confirmed against VR-D's names)

| Fields | Displayed meaning |
|---|---|
| model, refresh, eye_width, eye_height | headset model, Hz, recommended per-eye size |
| devices.left, devices.right | tracked-controller booleans |
| compositor_gpu_ms, compositor_cpu_ms | compositor frame timing |
| presents, dropped, reprojected | cumulative counts; presents is the percentage denominator |
| gpuMsTotal, gpuMsPathTrace, gpuMsUpscale, gpuMsWarp, gpuMsOther | runtime GPU pass times, exact C names |
| centreWidth, centreHeight, renderWidth, renderHeight, eyeWidth, eyeHeight | runtime sizes, exact C names |
| framesSubmitted, submitErrors, posesMatched, posesUnmatched | runtime counters, exact C names |

No new native API function is requested or invented. Missing/invalid measurements display ?, not false zeroes.
Info values in the test stand-in are explicitly marked SCRIPTED TEST and are not headset/GPU timing measurements.
VR-Q can compare this table directly to the module. The runtime owns its VR option layer and Frame Generation;
this Lua does not write Remix options or user.conf. V1 still refuses remote clients before loading the module.

## VR-Q handover and shared-document text

- Package vr/addon as garrysmod/addons/nlvr, a declared lua-addon root with no autorun, excluding .md/test files.
  The companion collector already picks up nativeloader_vr.lua and excludes its documentation. E changed no packaging.
- Native S1-S8/headset tests remain with their assigned tasks. E's S8 result is the real raster canvas and clean
  guard acceptance, not compositor submission. S6 still settles the provisional FOV and camera classification.
  Check native saved eyes/overlay pixels and actual quit/resource teardown, with the required locks. V2 was not started.
- CHANGELOG: VR uses ordinary 3D suppression and reversible proxy/child hiding, leaves desktop 2D and all engine
  convars alone, owns only the CalcView event, samples the same engine frame and pushes each sequence once.
- COMPONENTS/companion README: page lifecycle remains in nativeloader_vr.lua; vr/addon/lua/nlvr/client.lua owns camera,
  proxy and wrist logic. companion/tests/vr_standin.lua and vr_poc.lua/.py provide the non-shipping real-game proof.
- TESTING: 43 offline cases, both real SP/listen-host modes, 14 screenshots, 2 native raster PNGs, 1621 camera samples,
  zero duplicate/foreign calls, zero rendered-position error, and clean 2877-file PoC rollback. The deliberate
  blocked-command diagnostics are distinguished from unexpected errors. Native headset proof is still VR-Q.
- RESEARCH: engine SetString restriction and blocked fps_max measured in both modes; cl_drawhud/r_drawviewmodel
  normal client commands measured 1->0->1. GetCurrentViewOffset is actual, not standing-only. Main CalcView precedes
  PreRender, so a PreRender-only sample lags by a frame. The weapon proxy Think draws the active world weapon and
  re-enables its child (packages/fixes/.../lua/entities/rtx_pseudoweapon.lua); hiding just its parent is insufficient.
- Decision records: runtime boundary keeps post-centre 2D on the desktop; no global dispatch/VGUI interception;
  no engine convar mutation/bypassing blocked commands; event-local camera authority and once-per-frame sampling;
  per-entity Think/child visibility restored exactly. These follow the user's review without changing the binding
  VR architecture. ROADMAP: E review fixes/real-game Lua proof and Release gate complete; V1 integration,
  native spikes, independent review and user approval remain.

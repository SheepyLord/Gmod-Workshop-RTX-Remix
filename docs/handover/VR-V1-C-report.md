# VR-V1-C: runtime output

Current startup correction after the second runtime review: the VR creation list guarantees two
instance and four device names independently of FSR, six names in total. The five-name delta
measured in this report belongs to the original installation with FSR present;
VK_KHR_get_memory_requirements2 was then supplied by that optional library. See
[ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md) and the
[second-review report](VR-V1-Q-runtime-review-report.md) for the corrected code and renewed evidence.

Implemented locally on `vr-c`; the runtime clone is on `vr`. Centre rendering, stereo depth
gather, Vulkan submission, mirror, overlays, reversible preset, capture and timing work in the
PoC. **VR-D/VR-Q must carry the completion wait below into module pacing.** The camera ring
alone does not order SteamVR frame epochs. No shared API header change was needed.
Nothing was merged, pushed, published or imported into `packages/`.

## Accepted delivery and implementation (before review)

- Runtime clone: `out/worktrees/r17/out/runtime-src`, branch `vr`, commit `ef3389cf`.
- Patches **0042 to 0054**, exported individually, with exact `pending_patches.files` hashes.
  Published provenance and the packaged DLL remain unchanged.
- Accepted baseline `-NoImport` DLL: **418,315,776 bytes**, SHA-256
  `1a33a64ae06b8fe9e1d80e9ef515d51b165d81f64d4aee308b3876796d492059`.
  Keep the authoritative build in `_CompRelease_x64/src/d3d9/d3d9.dll` for VR-Q.
- Eight named exports, including Windows shim forwards; no additional DLL imports and no OpenVR
  import. The compiled 6,520-byte warp SPIR-V is embedded verbatim at offset 11,605,056, SHA-256
  `678fae5cadb65ea74f30662841e2b4bff4c2a51c2975c14bc0892d2f608745ee`.
- The shared header is byte-identical to VR-D's, SHA-256
  `645ac84ac0cd35b1731c444a7e20402b9db23e79102bdd0b742142cd4a206872`.
  A private export header satisfies MSVC linkage without changing that shared header.

All evidence paths below are relative to **the main checkout's `out/vr/c/`**. The probe sources
are `driver/driver.cpp`, `poc_c.py`, `gpu-math/gpu_math.cpp` and `collect_results.py` (uncommitted).
The data receipts are `results.json`, `gpu-samples.csv`, `binary-verification.json`, build logs,
and each run's `poc/session.json` array. Per-step `session.json` is the loader's own record.

`DxvkObjects` owns `RtxVr`; C exports use the existing registered D3D9 device. Start validates
and copies a request; the render thread resolves the module-supplied OpenVR interfaces. The
runtime neither loads the SDK DLL nor initializes OpenVR. Stop synchronously revokes interface
access, clears textures under queue exclusion and permits SDK shutdown. The render thread flushes
and drains outstanding copies before retiring images and restoring the ordinary output extent,
including exit to a menu. No GPU wait or diagnostic write holds the API request mutex.

The symmetric centre projection covers both eyes' rotated corner rays. Its inverse Jacobian
preserves central eye density, including cant/roll. The engine's original FOV remains separate
for main/view-model classification. Eye requests are frozen with the camera frame; IPD edits
reuse eye images. The existing runtime final-output image becomes the enlarged centre, with
normal upscaling underneath it. The game target/window keep their size.

Each compute gather uses full eye rotation/translation and primary axial depth. At an unresolved
discontinuity it retains the **observed farther coordinate**, rather than projecting that depth
back behind foreground. The final CPU/GPU tests explicitly verify background colour. A mono view
still cannot reconstruct hidden geometry or eye-dependent lighting; this is the agreed phase-1
approximation. Both submits and handoff use DXVK's submission lock after a command flush. Real
frames carry their matched pose; scripted frames omit the pose flag. Explicit application handoff
makes module-side WaitGetPoses queue-safe. The left eye is cropped/scaled into the original game
target, with later raster UI on top. VR present uses interval zero without editing `mat_vsync`.

Unique-sized raster canvases are copied on target changes, then uploaded through SetOverlayTexture.
Removal/rebinding clears the compositor texture and drains its copies before image retirement.
The fixed preset is **DLSS Performance, Ray Reconstruction, one to four bounces, renderScale 1**.
It retains scene lighting/sky, and forces DLSS/FSR frame generation, motion blur, chromatic
aberration, vignette, free camera and camera shaking off. One fileless layer above quality
presets owns these choices; Stop removes it. There is no new saved option/menu, so no new
`RtxOptions.md` or six-catalog entry is needed.

Capture asynchronously saves PNG eyes, centre, logarithmic depth, overlays and final mirror.
Depth PNGs visualize float depth in logarithmic 8-bit greyscale at tracing resolution. Seven GPU
timestamps in eight recycled slots separate lighting, upscaling, warp and other work. Total runs
from injection preparation through the later raster/overlay pre-present work. Other includes
scene/AS preparation, postprocessing, mirror/transfers and queue gaps within that span; desktop
WSI presentation is outside it. Status holds the latest resolved sample, normally eight rendered
frames behind. Incomplete scene/query sets are discarded. SteamVR's application metric is logged
separately.

## S2: enlarged output, unchanged window - passed

The first synthetic 2016 x 2240 eyes, with +/-5 degrees rotations, produced a **2392 x 2456 centre**
(traced 1387 x 1424 with provisional Balanced) in a **1280 x 720 window**. In 55 seconds:
**5,831 rendered and matched, zero unmatched**. Six PNG kinds: `flat-r2/no-submit/captures/`.

The desktop clamps tall windows at 2160 pixels. The exact-size control therefore used synthetic
2016 x 1968 eyes, producing **2392 x 2160**. Both cases used the same world camera, clear/noon
sky, DLSS Performance/RR and four-bounce limit. Flat uses the engine projection and VR its headset
union, so framing differs; flat image parity is measured separately with matching projections.

| Case | Output / window | FPS |
|---|---|---:|
| Published flat | 2392 x 2160 / 2392 x 2160 | 128.15 |
| VR centre + warp, no Submit | 2392 x 2160 / 1280 x 720 | 128.20 |

The VR FPS uses rendered-counter deltas while active, not the post-Stop FPS probe. Earlier
instrumentation measured 6.152 ms: lighting 4.603, upscale 1.316, both warps 0.048, post/output
0.185. Final Total/Other additionally include preparation and later raster work, so compare
those earlier totals only within their own scope. Evidence: `s2-r2/poc/`,
`s2-r2/no-submit-sized/captures/`, `results.json`.

## S6: main camera/history - passed

The game culling FOV was **145**, with a 16:9 window. The actual Index union is **114.072 degrees x
109.363 degrees**, tangents 1.541975 x 1.411383. Simple 16:9 frustum geometry needs 136.541 degrees horizontal
coverage for that vertical extent; 145 supplies margin. This is the tested choice, not a claim
about every Source FOV convention/window shape. CalcView returns CamData; RenderView's aspect
field is not part of that [documented contract](https://wiki.facepunch.com/gmod/Structures/CamData).

The long `vr-r5` run has **8,122 matched, zero unmatched**, and 68 camera diagnostics. Only the
initial transition is a cut. Every later cut would also have been logged; there are none.
The vertical projection stays 1.90874 radians. `vr-r4` explicitly printed queue mode **2**, vsync
**0**, fps_max **0**: **3,344 rendered/accepted, zero unmatched/errors/drops**. The real SDK
returned identity eye rotations with asymmetric tangents on this Index, despite the plan's
panel-cant assumption. Synthetic +/-5 degrees inputs exercise the general rotation path.
Evidence: `vr-r5/poc/submit/{console.log,remix-dxvk.log}`, `vr-r4/`, unit/GPU tests below.

## S3: Submit - passed with a module pacing requirement

The unconstrained queued run rendered 6,436 frames and had **139 failed eye calls**, error
**108, AlreadySubmitted**. Poses still matched. The next Lua-side WaitGetPoses could reset the
compositor epoch before the previous queued render thread submitted. Queue exclusion alone
cannot order that epoch against the module.

The completion-gated driver fixes this. Its final long run, `vr-r5`, is a 185-second timeline:

| Counter | Result |
|---|---:|
| Runtime rendered / accepted pairs | 8,122 / 8,122 |
| Failed eye calls / unmatched poses | 0 / 0 |
| SteamVR presents / dropped / reprojected | 16,606 / 0 / 8,608 |
| Raw SteamVR cumulative submits | 8,147 |
| Steady sampled CPU Submit mean / p95 | 0.201 / 0.240 ms |

SteamVR's raw counters include startup accounting and are retained alongside the runtime pair
count rather than equated. Seconds 35-45 used real Submit_TextureWithPose; other intervals were
scripted without the pose flag. Both worked. No device loss; normal quit and clean restoration.
The SDK is absent from the loaded-module list after Stop. Earlier gated runs: `vr-r2` 7,257/7,257,
`vr-r3` 8,235/8,235, also zero errors/drops. Initial failure: `vr/poc/submit/`.

**VR-D/Q:** before the next WaitGetPoses, wait for the previous output ticket, with a bounded
wait that breaks on Off/Failed/Stop. After getting poses, sample framesRendered and arm the next
ticket as that value + 1 when handing over the game frame. framesRendered now publishes after
both Submit calls/handoff, even for unsuccessful pairs, so an error does not wedge the fence.
Do not hold a module/SDK mutex while waiting or free-run the producer ahead of consumed game
frames. Install view hooks when the SDK/module is ready; waiting for a traced VR frame first
would leave startup unordered. Retain the camera ring: the fence handles pacing, the ring handles
pose association. This uses existing status fields and changes no header/version/loader.

## S8: overlay/mirror - passed

A **1027 x 259** game render target painted health/armour/ammo and a changing frame number.
SteamVR accepted it, reported it visible and returned the exact texture size, error 0. `vr-r5`
changed eye offsets by +/-2 mm then restored them (results 0), resized the same overlay to
**1029 x 259** (result 0), and removed it (result 0): **242 successful texture uploads**.
After removal, bound count and texture size are zero; GetOverlayTextureSize returns expected
missing-texture error 11. Visibility alone is not used as proof: uploads, dimensions and pixels
are checked together. Placement was scripted; controller/wrist attachment is VR-D/E integration.

`vr-r5/submit/captures/` contains 2468 x 2740 eyes, 2944 x 2752 centre, 1472 x 1376 depth,
overlay and 1280 x 720 mirror; all decode as PNG. Reconstructing the integer **2468 x 1388**
left-eye crop and scaling to the mirror differs by **0.722/0.874/0.881** mean RGB code values
out of 255. Pillow also antialiases; Vulkan uses four taps. The window shows the left-eye crop,
with subsequent native raster UI, and the overlay retains raster text/colour rather than being
a path-traced card. Evidence: `vr-r5/`, image hashes/dimensions and `mirror_check` in `results.json`.

## S7: 5090/Index cost and the fixed preset - passed

**RTX 5090, 32,607 MiB reported, driver 617.42**. SteamVR recommended **2468 x 2740 per eye at
90 Hz**, separation 68.5366 mm. Scale 1 gives **2944 x 2752 centre**, traced **1472 x 1376** by
DLSS Performance. No refresh preference, SteamVR setting or Steam registry setting was changed.
The pinned client has no session-only refresh request; using IVRSettings would change a setting.

The stable `vr-r5` window is **75.718-159.717 seconds**, 85 one-second samples, excluding capture,
eye-update, resize and removal transitions:

| Component | Mean GPU ms |
|---|---:|
| Lighting/path tracing (includes volumetrics, denoising, composition) | 6.838 |
| Upscaling/sharpening | 1.915 |
| Both eye warps | 0.084 |
| Other preparation / post / raster / transfer work in the span | 6.375 |
| **Runtime span total** | **15.212** |
| SteamVR application GPU metric, separately | 17.375 |

Sampled p95 runtime span: **17.006 ms**; SteamVR application GPU: **18.518 ms**. Application
throughput: **43.80 FPS at 90 Hz**, with reprojection and zero compositor drops. This is near the
intended 45-FPS half rate, not native 90. The preceding Performance run measured 44.83 FPS.
Provisional Balanced measured 39.21 FPS, with lighting/upscale means **8.574/2.442 ms** versus
**6.838/1.915**. This GPU headroom is why V1 chooses Performance. Auto/tier adaptation is V6.

| Refresh | Native budget | Half-rate budget | Supported conclusion |
|---|---:|---:|---|
| 90 Hz, measured | 11.111 ms | 22.222 ms / 45 FPS | Reprojected near-half-rate; measured GPU spans exceed native budget |
| 80 Hz, **inferred at the same size** | 12.500 ms | 25.000 ms / 40 FPS | 40 FPS has more margin; native 80 is unsupported by these costs |

80 Hz is an inference, not a second hardware run. Workload: `gm_construct`, one test barrel,
clear fixed noon, the RTX package's own addons, scripted head. This is not an FPS promise for
all maps/characters/addons. Windows/SteamVR share the GPU: `gpu-state.csv`, `gpu-processes.csv`.
Earlier development runs overlapped CPU compilation; the final long profile did not.
The final shader-only gap correction is checked separately below; PT/upscale/preset are unchanged.

## Flat mode/startup - no consistent regression observed

In this original FSR-present build, the off-state device delta was five supported optional extension names:

- Instance: `VK_KHR_external_fence_capabilities`, `VK_NV_external_memory_capabilities`.
- Device: `VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation`, `VK_KHR_win32_keyed_mutex`.

S1 showed all five missing from the published enabled lists. The second review now independently requests a sixth name,
VK_KHR_get_memory_requirements2, which FSR supplied in this original run (ADR 0157, linked above).
Timeline functionality was already enabled in Vulkan 1.2; no feature boolean is added. Actual enabled-name sets are retained,
including provider/platform names. There is empty device-owned CPU state, dormant hook predicates
and input-FOV bookkeeping. There is **no OpenVR load/call, thread, VR image/query allocation or warp
prewarm before Start**, and no new DLL import dependency. Stop retires owned images/removes the
preset at the render boundary. Status keeps last-frame metadata for diagnostics. No option file
is written by the feature.

Final alternating controls, 1280 x 720, same map/pose/options, clear/noon, queue mode 2 and no
compiler job in the series (`parity-r2`):

| Run | Runtime | Map-ready seconds | FPS | Median / p99 ms |
|---|---|---:|---:|---:|
| base-1 | published | 15.2 | 132.85 | 7.508 / 11.903 |
| new-1 | candidate | 13.6 | 125.03 | 7.850 / 18.665 |
| new-2 | candidate | 10.3 | 137.51 | 7.295 / 9.513 |
| base-2 | published | 9.6 | 134.24 | 7.506 / 10.217 |

Mean run medians: **7.507 vs 7.573 ms**, +0.066 ms (+0.87%); identical candidate runs vary by
0.555 ms. Mean map readiness: **12.40 vs 11.95 seconds**. No consistent penalty is distinguishable
from background variation; this does not prove mathematical zero overhead. An earlier series
included a compile and also showed mixed signs; all raw runs are retained.

Matched captures differ by **0.554/0.540/0.584** and **0.500/0.496/0.533** mean RGB code values
out of 255, with no visible behavior change. Off-state samples have zero VR frames/dimensions;
the SDK is absent. Every run quit normally and restored archived settings through poc_session.
`user.conf` was never changed or moved by rollback. The later gap fix changes only active-VR
sampling; no disabled-path behavior changed after these controls.

## Tests, pins and restoration

- `tools/test.ps1 -Config Release`: conventions, **30/30 CTest**, **842 Python tests**
  (29 + 26 + 787), all passed: `repo-test-final.log`. Post-report gate recorded below.
- Dedicated `_CompUnitTest_x64` `test_vr_math`: **72 assertions**, **0.01 s**, passed.
  Union bounds/density, +/-5 degrees rotation/infinity, distance, observed-background gaps,
  invalid sizes/NaNs, ring ordering/eviction/wrapped angles/fallback.
  `unit-build-complete.log`, `unit-test-complete.log`, runtime Meson test log.
- The **final compiled SPIR-V** independently ran on this GPU with float input/output textures:
  **5 dispatches, 6 assertions**. Near/far U **0.4799999893 / 0.4979999959**; disparity ratio
  **9.999984741**. +/-5 degrees rotation U **0.4562556744 / 0.5437443256**. Gap RGBA **(0,0,1,1)**:
  observed blue background, not red foreground. `gpu-math/results.json`, `run.log`, source.
  `binary-verification.json` proves the exact tested SPIR-V is in the delivered DLL.
- Final real-headset smoke of the corrected gap shader: recorded below after rollback.

Every game held the PoC lock; OpenVR scenes also held the VR lock. Normal VR_Init only; no null
driver, manual SteamVR launch/stop, consent automation variable or crash upload. The field/legacy
installs, depot bytes and Remix `user.conf` were not written. Original PoC trees were moved aside
and their listings verified on restoration; shared video settings were restored. Every completed
rollback is clean. The long-run receipt verifies **2,877 depot files**, no missing/size/hash
differences. The SDK unloads after Stop; SteamVR itself is left running. Large copied DLLs,
extracted package inputs and snapshot contents are removed after verified restoration; receipts,
source probes, logs and PNGs remain.

NoImport initially found nine stale submodule `core.worktree` pointers from the old checkout
location. Only those metadata paths were repaired; sources/commits were unchanged.
`runtime-git-metadata-repair.json` records before/after. No dependency was silently moved.

OpenVR **v2.15.6**, commit `0924064316de3effbcd1acf1e309182a2deb1c05`, from
[Valve's pinned SDK](https://github.com/ValveSoftware/openvr/tree/0924064316de3effbcd1acf1e309182a2deb1c05).
Header SHA-256 `1e6ed57199896cc1f7c5484e50fa18955e97be15be690beb28d998c877ead7fd`;
BSD license `f56ff606104d4ef18e617921a75c73ad73b5a1a1d70c69590c29de16919e04ad`;
test SDK DLL `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a`.
The fork's old header/provider is preserved; pinned SDK files bypass EOL conversion.

## Open / integration

1. VR-D/Q must implement the completion-ticket wait and view-hook startup ordering above.
   This is a measured caller requirement, using existing status fields. The disposable driver
   and successful traces are the reference.
2. VR-Q imports **one** reviewed runtime, packages it with the module/addon/bindings and checks
   the actual page and wrist attachment. No runtime binary is imported here. Claude's independent
   review and the user's milestone approval/merge remain outstanding.
3. 80 Hz is inferred; changing that setting and Auto/tier tuning belong to V6. Phase-1 hidden
   surfaces and view-dependent lighting remain for true stereo in V7. This unworn-Index test
   is not a human comfort assessment or a guarantee for other workloads/hardware.

## Shared-document / decision text for integration

**CHANGELOG:** Opt-in runtime VR output on the VR milestone branch: headset-density centre view,
full-transform depth stereo gathers, synchronized Vulkan Submit, left-eye mirror, raster overlay
sources, reversible Performance preset, PNG capture and GPU timing diagnostics.

**COMPONENTS:** `rtx_vr.cpp/.h`, shared `rtx_vr_api.h`, private `rtx_vr_exports.h`,
`rtx_vr_math.h`, `rtx_vr_png.h` and `rtx/pass/vr/vr_warp`. Device-owned state through
`DxvkObjects::metaVr`, separate request/OpenVR locks, no SDK loader in the runtime.

**ROADMAP:** VR-V1-C implemented; S2/S6/S3/S8/S7 settled on the Index. V1 awaits module pacing,
combined package/page/wrist integration and independent review.

**RESEARCH:** Record the five extension deltas, 2468 x 2740 recommendation/frustum/identity
rotations, queue-mode-2 camera evidence, failed unconstrained versus accepted fenced epochs,
pass timings/reprojection counters and mirror/background checks above. Source sites in the fork:
`dxvk_instance.cpp:763`, `dxvk_adapter.cpp:497` (extensions);
`rtx_camera_manager.cpp:102` and `:138` (input FOV);
`rtx_vr.cpp:58`, `:78`, `:134`, `:171`, `:180`, `:305`, `:403`, `:479`
(start/stop, projection, retirement, timing, Submit/explicit timing);
`vr_warp.comp.slang:40` (observed-background coordinate). The near barrel's logarithmic depth
codes 102-103 imply roughly 83-91 game units, consistent with its 100-unit centre distance and
radius; eye offsets therefore use game units against primary axial depth.

**TESTING:** Retained sources under `out/vr/c` reproduce this test with both locks for headset
runs. Build via `-NoImport`, verify API bytes and embedded SPIR-V, run dedicated CPU math and
standalone GPU synthetic dispatches, then the PoC driver. Use clear/noon, restore trees/settings,
and separate capture/resize transitions from steady timing. Read the driver's `poc/session.json`
array for acceptance, not the loader's per-step `session.json`.

**Decision proposal:** Keep the agreed centre/depth design and module-owned OpenVR. Use full
transforms, observed-background gap filling, original engine-FOV classification, camera-frozen
eye updates and the nearest-camera ring. Serialize compositor epochs with the completion counter.
Use a fileless highest-priority preset and five supported prerequisites. Retire images after
queue completion, outside the request mutex. Keep runtime elapsed spans distinct from SteamVR's
application metric. No accepted decision was rewritten.

## Final build smoke and gate

The corrected, embedded gap shader was tested on the real Index in `vr-r6` for a 75-second
scripted timeline, explicit queue mode 2: **3,345 rendered / 3,345 accepted / 3,345 matched**,
**zero Submit errors, unmatched poses, compositor drops or device loss**. SteamVR recorded
**6,707 presents / 3,352 reprojected**, raw submits 3,370. Real pose-tagged and scripted submissions,
+/-2 mm eye edits/restoration, 1027 to 1029 overlay resize and removal all succeeded. The overlay
uploaded **90** times. PNGs include the resized 1029 x 259 source. Stop returned Off, SDK unloaded,
normal quit and clean rollback. This is the final-DLL smoke; S7's longer stable-window measurement
is retained separately so capture/resize work is not mixed into that performance window.

Final post-report `tools/test.ps1 -Config Release` passed in this worktree: conventions,
30/30 CTest and 842 Python tests (`repo-test-delivery.log`). Final `-Verify` confirms all
**50 patches**, tree `ceb2b0880052948c9c5e6a3badc7c3ae50aa50ca`, two submodule settings and
two clones, and the delivered SHA above (`verify-complete.log`). The CPU math log is also kept
as `unit-math-meson.log`. `cleanup.json` records removal of **3,271,129,716 bytes** of copied
DLLs, extracted inputs and verified snapshot contents; the authoritative runtime build, PNGs,
logs, receipts and source probes remain. All restoration receipts are clean, including the final
smoke and alternating series. No game remains running in the PoC. SteamVR server PID 27812 and
compositor PID 49804 remain running. Every task commit uses the configured identity and required
Codex trailer; neither repository has uncommitted source changes (the two declared runtime clones
remain intentionally untracked).


## Review follow-up: code paths and measurement plan

The accepted delivery above is the historical baseline. Follow-up patches start at 0055 on
these same branches. All follow-up text is ASCII encoded as UTF-8; dimensions use x, rotations
use +/- and degrees, ranges use to or -. The exported 0049 message contained a literal escaped
apostrophe; that message is repaired, its pending hash updated and its code diff unchanged.
Accepted fork commits are not rewritten. The byte audit covers authored sources and commit/patch
messages as well as this report and the VR README entry; pinned upstream SDK bytes are preserved.

Pose matching now compares the relative rotation of normalized forward/up bases. The renderer
passes its camera vectors directly. Position tolerance remains 0.5 game units and rotation
0.5 degrees. Tests include exact alternate Euler branches at +/-89 degrees, degenerate yaw/roll
splits at +/-90, near-pole cancellations within tolerance, wrong up/roll and position rejection.

The centre now includes translated corner positions at a nearest head-axial depth of 0.5 m,
as well as directions at infinity. This is a fixed V1 policy, not a new saved option. On the
measured Index the expected horizontal tangent margin is 0.0342683/0.5 = 0.0685366. Density is
kept, so expected centre width rises from 2944 to 3072 (4.35%); eye/window sizes do not change.
Captures will compare both outer eye edges with a patterned plane at that depth. Objects closer
than the policy and foreground missed by a backward gather remain phase-1 limits, not a promise
of complete near-field visibility.

Fine GPU stages cover preparation/AS, path/volumetrics, demodulation, denoising, composition,
upscaling/Ray Reconstruction, post/tone mapping, warp, mirror, capture copies, native Submit,
late raster and final overlay transfers. Command-list start/end queries identify gaps in the
application queue. SDK transfer/handoff intervals are separate elapsed spans, since client code
cannot split their internal GPU work from their host/IPC waits. Other submitted contexts are
tracked too; an untracked submission invalidates the CPU-gap attribution instead of silently
calling it idle. The five public times remain sums. Each capture receives its own resolved
frame timings.json; logs contain periodic RTX VR profile JSON. Render-side thread CPU running
time and a driver-side game/fence/WaitGetPoses breakdown will distinguish GPU cost from the
serial completion hand-over. Ray Reconstruction's denoising is fused in the upscaler; the native
NRD denoising bracket may therefore be effectively empty with this preset.

### No traced scene

Before the first valid 3D camera/scene, Start remains STARTING, with no submitted eye image;
SteamVR supplies its own environment/loading presentation. During an established session, a
map/menu interval without a traced scene produces no new eye pair. SteamVR owns the retained
previous submission and can reproject or fade to its loading/grid presentation according to its
own state. The runtime does not synthesize a new loading scene. It keeps VR resources and the
preset for the next traced frame. Dirty raster overlays may still update, and the submission
hook can still issue explicit timing on ordinary raster submissions. The status enum has no
suspended state; counters stop advancing until tracing resumes. Capture requests await a traced
frame. Logs mark the transition. No scene is a normal pause, not a device loss.

### Reset, loss and lock order

A D3D9 window resize/reset keeps the Vulkan instance, physical/logical device and graphics queue.
D3D9DeviceEx::ResetSwapChain calls D3D9Rtx::ResetSwapChain and emits the normal screen-resolution
reset; D3D9SwapChainEx::Reset synchronizes presentation/rebuilds the window buffers. At the next
VR injection the centre extent is selected again and the mirror uses the new game-target size.
The eye images/interfaces/preset/session remain. A transient reset can invalidate history; it
is not a new VR Start. A minimized/occluded window can stop rendering/presenting: while it does,
there is no fresh eye pair and the preceding no-scene presentation behavior applies. Restoring
it resumes the same session if the same device is retained. Safe resize/restore will be tested;
no GPU crash will be deliberately induced.

Lock walk, including normal reset synchronization:

- stop takes request, publishes Off/generation and releases request; then OpenVR; then submission
  synchronization/queue exclusion. It clears textures, nulls interfaces and returns. No request
  lock is held while waiting on OpenVR/queue. Resource retirement is later, on the render side.
- submit takes OpenVR, rechecks active/interfaces, flushes commands, then queue exclusion. Its
  small status updates take request under OpenVR. Recording hooks use their own mutex, release
  it before submission/SDK work and never acquire OpenVR while holding it.
- present processes private raster resources; SDK texture updates take OpenVR, flush, then queue.
  Only small counters take request. Capture/diagnostic I/O and GPU drains are outside request.
- beforeSubmission tries OpenVR without blocking. When called recursively by a flush under
  OpenVR it skips, avoiding a self-deadlock. Otherwise it takes queue exclusion for explicit
  timing and releases it before normal DXVK enqueue. noteSubmission's recording lock is released
  before that try. GPU-coverage readback does not hold OpenVR/request.

The D3D9 reset waits for CS/presentation work but VR never acquires the D3D9 device lock, so this
adds no inverse path to the preceding locks. Request is never held across an OpenVR acquisition.

Actual VK_ERROR_DEVICE_LOST is not a recoverable resize. dxvk_queue.cpp::handleDeviceLost
captures diagnostics, waits for the existing consent/crash path and terminates the process;
second loss observers wait for that termination. DXVK ceases normal submissions. VR has no live
Vulkan-device recreation path or reliable opportunity to publish a fresh Failed status then.
The headset can only retain/fade the last valid image until the process/client is gone. Stop's
normal queue wait has no independent timeout if the GPU/submission worker is wedged or handling
that fatal path; it is not a crash-recovery guarantee. Existing prompt handling declines No/OK
and never sets upload-consent automation. A genuinely replaced device would require orderly
Stop/SDK shutdown, then a new Start; old VkImage/device/queue pointers cannot be reused.

Measured follow-up results and the final build/gate receipts follow below.


The first fine-timing pilot exposed a fork-specific readback hazard: query resets are GPU
commands, so availability can still describe a previous use until that reset executes. Patch
0059 waits for a recording completion notification before reading/recycling its timestamps.
The corrected pilot separated a 7.449 ms late-raster span into 0.006 ms application work and
7.443 ms without a new application batch. It replaces the invalid busy-list estimate from the
first pilot. Native SDK intervals remain opaque transfer spans, not CPU idle. The diagnostic
brackets add one small flush after Submit; results include that instrumentation, without a
steady-render GPU-idle call.

The shutdown walk also required explicit VR onDestroy before common query/image allocators
are torn down. D3D9DeviceEx flushes/synchronizes and idles, then DxvkObjects::onDestroy now stops
and clears VR first. This covers exit without another render frame after Stop. The later VR
destructor has no owned handles left. No crash-recovery guarantee is added for fatal device loss.


## Review measurements (current runtime)

Evidence is under the main checkout's `out/vr/c/review/`. The executable is built with
0055-0059 on top of the accepted result. The shared API header remains byte-identical.
The dedicated math target passes 162 checks in 0.01 s, including the pole and finite-depth
coverage cases and interval-union accounting. An initially incorrect test assumed that half-IPD
always adds to a toe-in directional extremum; translation can move that extremum inward. Patch
0058 tests the equality on parallel eyes and tests toe-in coverage at infinity and finite depth.

### Fine times and the limiting stage

The three-minute paced run and the 100-second unpaced control use identical recommended eyes,
3072 x 2752 centre, 1536 x 1376 DLSS input, view, clear/noon, RR/Performance/four-bounce preset.
The unpaced control initializes the real SDK to read those same parameters but sets NO_SUBMIT
and omits both the completion fence and WaitGetPoses. It is not a different-resolution control.
Neither run overlapped compilation or the Release gate. Means below use 83 paced logged profiles
(poses 2000 to 7000) and 92 unpaced profiles (3000 to 8500), all with known coverage and zero
untracked submissions. GPU-clock queue gaps are separated from recorded command-list work;
this is not a hardware-wide utilization counter and other desktop programs still share the GPU.

| Component, ms | Paced Submit | Unpaced NO_SUBMIT |
|---|---:|---:|
| Scene preparation and AS | 0.348 | 0.530 |
| Path tracing, volumetrics, NRC/RTXDI/GI | 6.291 | 6.318 |
| Demodulation | 0.049 | 0.042 |
| Separate native denoising | below 0.001 | below 0.001 |
| Composition | 0.331 | 0.295 |
| Upscaling including fused Ray Reconstruction denoising | 2.159 | 2.117 |
| Post-processing and tone mapping | 0.302 | 0.292 |
| Two eye warps | 0.111 | 0.083 |
| Mirror | 0.008 | 0.008 |
| Capture copies (outside capture transitions) | below 0.001 | below 0.001 |
| SDK Submit/handoff transfer interval | 0.056 | below 0.001 |
| Late application raster work | 0.005 | 0.005 |
| Final overlay-transfer interval | below 0.001 | below 0.001 |
| No new application batch, outside SDK spans | 9.395 | 0.012 |
| Total elapsed runtime span | 19.055 | 9.703 |

The SDK rows are elapsed transfer/handoff intervals and can contain SDK/IPC waiting; they are
not presented as pure shader busy time. Ray Reconstruction fuses its denoising in NGX, so there
is no cheap internal separation from its upscaling; the native NRD bracket is effectively empty.
There is no unexplained residual: the public Path field sums path/demod/denoise/composition,
Upscale and Warp retain their groups, and Other sums preparation/post/mirror/transfers/raster
plus the measured queue gap. All four add to Total. Capture `timings.json` includes the exact
capture frame/pose and the fine split; each periodic JSON record includes coverage and the sums.

The paced status-counter window measured 44.91 FPS, versus 101.62 without fence/pose pacing.
In the paced loop, game work between driver calls takes 4.541 ms wall, the completion-ticket
wait 9.071 ms and WaitGetPoses 8.615 ms. These account for a roughly 22.22 ms cycle. Running CPU
averages are 4.602 ms on the game thread and 3.392 ms on the render-side CS thread; render-side
injection wall time is 1.925 ms. GetThreadTimes is quantized, so its running time is averaged
across frames rather than interpreted from isolated zero/15.625 ms samples.

The current implementation is therefore limited by the serial game/render completion hand-over
and headset pacing, not by either CPU thread's active work alone or a GPU executing for 19 ms.
About 9.66 ms of the paced span is covered application/SDK work, with another 9.39 ms awaiting
new application batches. Removing the hand-over/pacing exposes roughly 102-FPS capacity in the
same workload. This does not prove that removing synchronization is safe: the earlier 108 errors
show why the ordering exists. VR-Q/V6 can improve how that ordering is integrated; reducing
DLSS resolution alone will not remove this synchronization limit. The original 43.8-FPS/15.212-ms
numbers remain historical, not an exact decomposition of a run with the newer margin/brackets.

### Near outer edges

`edge-models` compares the accepted DLL and current DLL with the same mesh carriers at 0.5 m
head-axial distance and narrow coloured strips just inside each eye's outer edge. The mesh
centres are computed from the full SDK eye transforms and tangents. The first DrawQuadEasy
probe did not enter the traced geometry; it is retained as an unsuccessful probe and is not used
for this conclusion. The successful probe uses scaled clientside mesh blocks instead.

Before the margin, the eye edges show clamped carrier/background and lose both coloured strips.
In the outer 32 columns and vertical range 1100 to 1650, green marker count is 0 before and 6302
after on the left; magenta count is 0 before and 5089 after on the right. New marker bounds are
left x=0 to 19, y=1203 to 1537 and right x=2449 to 2467, y=1234 to 1531. Captures and numeric
masks are in `edge-models/edge-{before,after}/captures/` and `edge-measurements.json`.
`outer-edge-before-after.png` is an analysis crop, in order before-left, after-left,
before-right, after-right; original eye/centre/depth images are kept.

The cost is exact in target pixels: centre 2944 x 2752 to 3072 x 2752 (+352256 pixels, 4.35%),
tracing 1472 x 1376 to 1536 x 1376 (+88064 pixels, 4.35%). A single RGBA16 centre image adds
2818048 bytes (2.6875 MiB); centre-resolution-dependent resources scale similarly while fixed
resources and the two submitted eye targets do not grow. Actual pass costs are measured above;
there is no isolated causal millisecond claim across different binaries/queue schedules.
The guarantee is for depths at least 0.5 m. Closer geometry and newly exposed thin foreground
that a backward gather never observes remain phase-1 limitations. The policy can be lowered for
hands later, with a corresponding pixel cost; V7 is the complete stereo solution.


### Safe resize, minimise and no-scene observations

`lifecycle-window` prints queue mode 2 and renders the four pole views with the alternate pose
representations. It ends with 6199 rendered/accepted/matched pairs, zero unmatched/Submit errors,
zero compositor drops and a normal Off after Stop. The OS watcher changes the client rectangle
from 1280 x 720 to 960 x 540, then 1600 x 900; GetClientRect confirms both. Runtime mirror PNGs
have those exact sizes. Centre stays 3072 x 2752, tracing 1536 x 1376 and eyes 2468 x 2740.
The same session survives a three-second minimise/restore (17:54:19 to 17:54:22 UTC). Window
and minimise action JSON, console/runtime logs, module lists, captures and clean restoration
receipt are under `lifecycle-window/`.

The guard rejected the initial Lua mat_setvideomode requests. They are not counted as coverage.
An exploratory direct-console request in `lifecycle` caused a 640 x 480 video transition and a
long interruption; it is retained as exploratory evidence, not the safe resize result. The final
safe test uses normal OS window resizing without disabling the guard. This validates window/WSI
and game-target resizing, not live replacement of the Vulkan device. Logical D3D9 reset and fatal
loss behavior above are code-path statements, not a deliberate crash test.

The traced counter holds at 4258 through a no-trace interval. The compositor mirror was read
successfully before and during it (3024 x 3360, API result 0). It shows the retained world under
the existing SteamVR dashboard, not a new runtime loading picture. Mean RGB difference between
the before/paused composited captures is only 0.372/0.313/0.325 code values out of 255. SteamVR
owns dashboard/fade/reprojection behavior; a different dashboard/focus state can present its
loading/grid environment. Rendering then resumes in the same session and reaches the 6199-pair
final count. Mirror priming before its first valid format is not used as image evidence.

`scene-pause` additionally suppresses RenderScene without changing the ray-tracing option. The
runtime logs no traced scene, holds the counter at 612, and logs resumed tracing; the probe
confirms advancement to 635 afterwards. This separates absent world draws from an option toggle.
The disposable main-thread completion wait makes these pauses much longer than their nominal
CurTime timer intervals: the requested release is reached at about 53.1 s and resumed output at
59.6 s in that test. This is an integration limitation of the reference driver, not GPU execution
or an automatic Vulkan recovery. VR-D/Q must not wait on an impossible eye-output ticket on the
game thread during menu/load/no-scene states. Use its own lifecycle/scene readiness and a cancellable
worker wait; do not copy the two-second fallback into the game loop unmodified. Runtime state
remains Running while the session is alive, because v1 has no public Suspended state.

No GPU loss was induced. On a real loss the existing fatal DXVK path stops normal queue work,
handles diagnostics/consent and terminates; VR has no device-recreation recovery. A wedged GPU
or fatal worker can delay normal Stop queue synchronization, so the normal lock-order guarantee
is not a bounded GPU-crash recovery guarantee. The unload/device-lifetime cleanup added in 0059
applies to orderly teardown.

All follow-up sessions quit normally and restored their PoC trees/settings. No authored user.conf
was changed. The follow-up byte audit is `review/encoding-audit-full.json`: authored current source
content and new subjects/messages are ASCII UTF-8; historical patch diffs can contain a valid
UTF-8 BOM and upstream text. Pinned SDK bytes are unchanged. The accepted source history's literal
escaped apostrophe is left immutable, with only its exported 0049 message repaired.

Final follow-up build/gate/cleanup receipts are recorded below.


## Review handover build and gate

The follow-up runtime clone is on `vr` at `62736bda` (0055-0059 exported separately).
Final `-NoImport` d3d9.dll: **418332160 bytes**, SHA-256
`73adc01d4ad83c50b48ccc1457c8cc7457916bec668731de719925fdd6779a8c`.
`review/verify-final.log` proves the exact base plus **55 patches**, tree
`8ddaf48fc38d2c8c8632b8e007646e40d8022a42`, two submodule settings and two clones.
`review/build-02.log` records both build passes. `review/results-final.json` verifies eight C
exports, no OpenVR DLL import, unchanged shared-header SHA
`645ac84ac0cd35b1731c444a7e20402b9db23e79102bdd0b742142cd4a206872`, decoded PNGs, clean
cohorts and fine/public GPU sums. The authoritative DLL remains in the runtime build; no DLL
was imported into packages. SDK/device headers are still pinned byte-for-byte.

`tools/test.ps1 -Config Release` passed in this worktree: 30 CTest tests, 842 Python tests and
repository conventions (`review/repo-gate.log`). Dedicated runtime math passed 162 checks in
0.01 s (`review/unit-test-02.log` and the runtime Meson log). The five review requests are covered
by the ASCII repair/audit, fine timing/controlled pacing experiment, orientation tests/live pole
views, before/after near-edge captures, and the lifecycle code walk plus safe resize/minimise
and retained-scene observations.

VR-Q starts from this result. Its main remaining integration duty is the completion ordering
without blocking the game thread during absent-scene states. Runtime/device-loss limitations,
0.5 m coverage policy and opaque SDK transfer intervals are explicit above. No additional API
version or shared header was introduced. Full device replacement/loss was not induced. No
branch was pushed or merged, no workflow was started, and nothing was published.


The final post-text Release gate also passed (`review/repo-gate-final.log`, 30/30 CTest and
842 Python tests). `review/cleanup-final.json` records 2992589839 bytes of copied DLLs, extracted
inputs and verified snapshot contents removed. Every follow-up restoration is clean, including
scene-pause and lifecycle-window; user.conf was never moved/changed. No PoC game remains.
The authoritative runtime build, source probes, JSON receipts, logs, original captures and
analysis crops remain. SteamVR server/compositor were left running. Final report bytes decode
as UTF-8, all report content is ASCII and it contains zero damaged question marks. Current
source content and new patch headers/messages were byte-audited; historical accepted fork
messages remain immutable. All commits retain the configured identity and Codex trailer.

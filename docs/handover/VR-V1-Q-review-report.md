# VR-V1-Q independent review and pacing follow-up

Current startup correction after the second runtime review: the VR creation list guarantees two
instance and four device names independently of FSR, six names in total. The five-name delta
measured in this report belongs to the original installation with FSR present;
VK_KHR_get_memory_requirements2 was then supplied by that optional library. See
[ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md) and the
[second-review report](VR-V1-Q-runtime-review-report.md) for the corrected code and renewed evidence.

This supersedes affected implementation/API descriptions in [the initial Q report](VR-V1-Q-report.md).
Work stays local on vr-q and the runtime clone's vr branch. Same configured author and Codex trailer;
no push, merge, publication, workflow, field-install change, SteamVR shutdown or settings change.
Evidence: main checkout `out/vr/q/review/`. The review was read in full at
`out/vr/review/independent-1.md`; its baseline d10a00c predates several Q corrections.

## Review numbers

1. **Trust boundary:** Start refuses openvr_dll, manifest and runtime_dll from Lua. The module
   resolves the SDK/manifest relative to itself. Timeline/Capture accept a strict logical name
   below garrysmod/data/nlvr, with reserved Windows names/links refused. Automation alone sets
   process environment NLVR_TEST_ROOT under out/; the driver copies timelines and collects images.
   Probe exposes SDK presence as boolean. Native policy tests and six actual Lua negative calls
   test the removed keys and escaping capture names before SDK initialization. The README states
   every client script, including server-supplied Lua, can invoke the API and defines its limits.
2. **Nil frame:** current Q already held the last frame/camera. A new regression returns nil after
   a valid head while supplying a different engine origin/angle; it requires the exact same view
   and zero additional pushes. Transient nil/message also holds the camera until error handling ends VR.
3. **Paused lifecycle:** the native worker polls events at 20 ms independently of Lua, acknowledges
   quit with AcknowledgeQuit_Exiting, cancels/cleans up and preserves the reason in off. Page polling
   is active-session PreRender gated by RealTime. A native test emits quit without BeginFrame/Events;
   a real SP test uses timeline quit_at and the escape menu, never quitting SteamVR. Wall time
   **9.713 s**, CurTime advance **0.00835 s**, normal session end, unchanged original SteamVR PIDs,
   no Lua errors and clean rollback (`paused-quit/`).
   The shipping smoke also tested native stopping -> off before Lua requested Stop. The old off
   acknowledgement could leave view hooks installed; both transitions now clean the add-on
   idempotently, with a new regression for this ordering. The package repeats the paused quit.
4. **Timeout ticket:** Q's runtime already stopped counting unposed frames; the old review premise
   did not hold on that runtime. The serial path remains temporarily for comparison. Final handling
   follows the measured pacing decision below; the render mode has no module completion ticket.
   The first long tiny-motion control nevertheless exposed a distinct stall: nearest-camera
   matching could choose an already-consumed pose instead of a nearly identical pending pose.
   Patch 0064 filters candidates by consumed sequence; its regression reproduces an exact older
   match plus a 0.00001-unit newer camera. All **167** CPU projection/warp/pose checks pass. The
   driver now requires continued eye-counter progress, not merely equal rendered/accepted counts.
   The original construct-serial/construct-render folders are developmental, not final comparisons.
5. **Nil/message errors:** both Lua files read native results. Changed messages are logged; thirty
   consecutive frame failures or ten lifecycle-poll failures end the session with the reason. A
   stable error logs once. Failed overlay Start calls are errors, including creation details.
   Side-channel overlay placement failures do not throw away an acquired frame; they are surfaced
   in Info.frame_error and handled by the wall-clock lifecycle poll. New tests use nil/message,
   rather than pretending native functions throw Lua exceptions.
6. **First frame:** SDK-ready starts the producer, State reports running independently of renderer
   STARTING, and waiting for a traced scene imposes no 10 s deadline. The first render-side
   WaitGetPoses primes its epoch before the first fresh-camera Submit. Native tests require this
   readiness and successful pose acquisition beyond an injected old startup deadline.
7. **Immediate restart:** Q's stopping acknowledgement already fixed this. The async-stop test
   requires stopping, refuses restart and enables it only after off; the new paused-capable poll
   makes the acknowledgement work with the escape menu open as well.
8. **Invalid head:** pending poses whose head is invalid carry the no-submitted-pose flag, so the
   compositor uses its own pose. Native regression invalidates a previously valid HMD and checks
   the pushed flag. The add-on holds the last valid head for the game camera.
9. **Unplaced wrist:** requested visibility and successful placement are separate. A sleeping or
   disconnected hand stays hidden; reconnection places/shows it; loss hides it. Native tests
   require hidden -> visible -> hidden through device connection changes.
10. **Recentre:** nl_vr_recenter and translated Recentre VR button relatch yaw and standing XY on
    the next fresh sequence, preserving physical height and avoiding a duplicate push. The test
    checks explicit position/yaw arithmetic. Moving/turning by controller remain V2. The first
    CalcView caller deciding the frame's predicted origin remains a documented engine-hook limit.

## Render-side implementation and measurement

Runtime patches 0062/0063 implement wire API version 2 and the Start render-pacing flag. Both
header copies match byte-for-byte apart from line endings. FramePose includes QPC acquisition/
target times; Status exposes measured scheduling/pacing fields. In render mode Submit and handoff
are followed by WaitGetPoses on the render-side CS thread. Neither request mutex nor Vulkan
queue exclusion spans that wait. The SDK-call mutex does: Stop outwaits the current SDK call,
then revokes pointers. OpenVR offers no cancellation for WaitGetPoses, so there is no hard
independent time bound if SteamVR itself stops answering; measured waits/acknowledgements are reported below.
Explicit timing is keyed by compositor epoch, not desktop device-frame ID.

BeginFrame uses GetDeviceToAbsoluteTrackingPose, next-vsync time and vsync-to-photons, plus
pipeline feedback from matched submitted pose timestamps and compositor frame timing. There is
no guessed fixed extra frame count: it starts uncalibrated and updates from resolved timings.
The feedback is scheduling-derived, not a panel/sensor ground-truth measurement. The API formula
for next photons assumes no extra buffering, which is why measured pipeline lead is added.
Sources: [Valve pose prediction](https://github.com/ValveSoftware/openvr/wiki/IVRSystem::GetDeviceToAbsoluteTrackingPose),
[Valve frame timing](https://github.com/ValveSoftware/openvr/wiki/Compositor_FrameTiming).

The 75 s pilot (`pilot-render/`) accepted **4031/4031 pairs**, zero errors/unmatched/drops.
BeginFrame mean **0.074 ms**, median **0.070 ms**, p99 **0.137 ms**, no completion wait; actual
Lua thread CPU **4.47 ms** per accepted pair. Throughput over its mixed capture/gesture window
was **52.28 FPS**, not a native-90 claim. Long comparisons use the same map, preset and timeline;
continuous unique head motion after the early captures avoids identical-camera ambiguity in age measurements.

The four final comparisons are construct-serial-r2, construct-render-r2, house-serial-r2,
house-render-r2, each **310 s active**, each with real submits and the same recommended 2468 x 2740
eyes at 90 Hz, centre 3072 x 2752, Performance/RR/1-4 bounces and fixed sky/camera fixtures.
Raw per-run summaries plus comparison.json retain accepted-pair rates, cumulative stats,
CPU/GPU spans and prediction scheduling distributions. The initial uncorrected runs are excluded.

Corrected **construct-serial-r2**: **44.9968 FPS**, zero Submit errors/unmatched/stalls for 310 s.
**construct-render-r2**: **88.7444 FPS**, zero Submit errors/unmatched/stalls for 310 s. Estimated
display age changes **45.751 ms mean / 48.868 p95** to **36.076 mean / 36.305 p95**. Render-mode
prediction timing error is **+0.321 ms mean / +0.738 p95**, range -10.071 to +24.589 ms; these are
SDK-scheduling estimates, not an optical-motion latency measurement. Serial scripted input
samples now without a future timeline offset, so its prediction error equals its displayed age.
Captures/startup are excluded from steady windows. All four final runs pass the new progress check.

| 90 Hz / scale 1 | Serial construct | Render construct | Serial house | Render house |
|---|---:|---:|---:|---:|
| Steady accepted FPS | 44.9968 | **88.7444** | 33.0183 | 33.0450 |
| Whole accepted pairs | 13958 | 27358 | 10241 | 10253 |
| Whole presents | 27933 | 27924 | 27974 | 27974 |
| Whole dropped | 2 | 0 | 0 | 0 |
| Whole reprojected | 13993 | 729 | 23091 | 22987 |
| Steady reprojected/presents | 50.123% | **1.907%** | 82.470% | 82.022% |
| Failed Submit / unmatched | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Command + SDK GPU work ms | 9.694 | 9.238 | 14.384 | 14.448 |
| GPU-clock queue gap ms | 6.847 | **1.948** | 7.070 | 7.684 |
| Game-thread running CPU ms/pair | 4.708 | 4.082 | 12.567 | 12.795 |
| Render CS running CPU ms/pair | 3.385 | 3.018 | 8.072 | 7.722 |
| BeginFrame mean ms | 17.639 | **0.073** | 9.342 | **0.089** |
| Render-side Wait mean ms | 0 | 8.093 | 0 | 10.421 |
| Estimated display age mean ms | 45.751 | 36.076 | 67.210 | 77.390 |
| Estimated display age p95 ms | 48.868 | 36.305 | 80.566 | 82.326 |
| Prediction timing error mean / p95 ms | 45.751 / 48.868 | **+0.321 / +0.738** | 67.210 / 80.566 | **-0.989 / +8.101** |
| Measured extra pipeline intervals mean | 2.014 | **1.066** | 4.090 | 5.027 |

Serial timeline input samples at pose acquisition without forward prediction, so its timing
error equals displayed age. Render input evaluates the timeline at its predicted target, just
as physical input is explicitly predicted. These timing errors describe the compositor's
estimated first-view schedule, not an independently measured optical/angular tracking error.
The untouched physical headset is unsuitable as ground truth for synthetic head motion.
Render error ranges are -10.071..+24.589 ms (construct) and -14.895..+11.066 ms (house).

**Decision: render-side pacing is V1's only module mode.** The module no longer contains a
WaitGetPoses call, completion ticket, waitable timer or serial wait. Findings 4 and 6's serial
mechanism is removed. Historical comparison source/package is retained for reproduction;
new Lua Start refuses pacing=serial. Runtime's flag still specifies the wire behavior.

The game is genuinely paced by engine/DXVK queues: render-mode BeginFrame is 0.073/0.089 ms,
and game running CPU is 4.082 ms within an approximately 11.27 ms construct frame, not a spin
for the rest. Its steady rate is within 1.4% of 90 Hz, with residual misses rather than a forced
45 Hz alternation. SDK throttle samples are 240 at zero throttled frames / 6 at one in construct
render mode, versus all 246 at one in serial. On the heavier map GPU work exceeds the 11.111 ms
budget and game CPU alone is about 12.8 ms: it cannot lock to 90. SDK throttles one or two frames
and reprojects at about 33 FPS, with no Submit error or frozen counter. Achieving native 90 there
requires less scene CPU/GPU work, not another main-thread pacing wait.

At unchanged size, **80 Hz is derived only**: 12.5 ms native / 25 ms half-rate budget. Construct's
9.24 ms work has 3.26 ms GPU margin at 80; house's 14.45 ms exceeds native 80 too. This is not a
measured 80-Hz throughput promise. No refresh setting was changed.

Stop outwaits the SDK mutex. Accepted render waits reached **19.518 ms** on construct and
**36.912 ms** on house over the whole runs; steady p95 is 8.314 / 25.680 ms. These observed
bounds do not turn OpenVR's blocking API into a hard timeout. All Stop/off acknowledgements
and actual game quits completed normally; no SteamVR process was ended.

Both modes retain correct upright head-following eye captures and left-eye mirrors at the
same dimensions. World crop mean RGB errors are at most **0.777/255** on construct and **1.889/255**
on house in either mode (image-checks.json); full original PNGs/pose/capture timing remain.

## Validation and remaining receipts

Final native regressions: **16 cases pass**, including 5000 acquisitions against a stalled fake
renderer with zero module waits. Page/add-on/catalog: **55 cases pass**. Native
held-init entry calls remain responsive (observed maximum 9.42 ms while fake init held 1000 ms).
The shared-header identity gate passes; runtime CPU math passes **167 checks**. Experimental
builds all used NoImport; only the selected final runtime was imported for this follow-up.
Runtime: **418337280 bytes**, SHA-256
`2a6aca62d0102b061fa27f433b4ccaa0bedbbee57f159150b71cc609b32fa249`.
Module: **445952 bytes**, SHA-256
`f4ba7d17058c269666c1b3dffd5aaf65730cfe8421cf52c5ce9ae965a79d7dbb`.
Final local package: **out/dist/gmod-rtx-remix-0.0.0-vrq.review-final2.gma**, **1785 files /
2185372922 bytes**, content digest prefix **ac0dcf2ca785fcda**, checked by nlctl. The final
shipping-module smoke (**final-smoke-r3**) passes seven actual Lua boundary refusals, native
quit while paused, exact Source convar/live upscaling restoration, absent SDK after off and
only the permanent menu hook/no session timers. No SteamVR shutdown was used.

**tools/test.ps1 -Config Release PASS** on final implementation commit **fb6c462**: **34/34
CTest entries**, Python **29 + 26 + 855 = 910 tests**, **7 availability skips**, no failures,
ending All checks passed. Main group time **111.445 s**. Full normalized receipt is
**out/vr/q/review/build/gate-release.log** in main; the raw log is this worktree's
out/vr-review-release-gate2.log. Subsequent commits only fill the report. The original final-smoke
baseline failure was test-only: cold PreRender sampled the sky before queued fixture commands
latched; the probe now waits for actual values. Raw failures remain as development evidence.

All **11 follow-up** restorations are verified clean, including recovery through --rollback of
the interrupted, excluded old construct-render attempt. Protected user.conf hashes match, depot
verification runs, Source/Cloud settings restore before normal quit, and no PoC game or stale
task lock remains. SteamVR's original server/compositor/monitor remain running. No field install,
Steam settings, launch options or registry settings were changed. Initial-round cleanup refusal
remains recorded in the original report; no rejected deletion was retried.

## Current user preview and remaining limits

From vr-q (fresh evidence name):

```powershell
python tools/vr_session.py --package out/dist/gmod-rtx-remix-0.0.0-vrq.review-final2.gma --evidence H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/vr/q/review/user-look-01 --look --seconds 900
```

The driver snapshots/installs the local package and starts the PoC. Use Start VR on the page
or nl_vr_start. After putting the headset on use **nl_vr_recenter**, or Recentre VR, to relatch
standing XY/yaw. Exit VR returns flat; finish with **nl_vr_demo_done** for shared-setting restore,
normal quit and verified rollback. The optional timeline command argument is now a data name,
never an absolute path. Old comparison packets require their retained source/probe versions.

Controller locomotion/turning are V2. True stereo/disocclusion limits remain V7. Other hardware,
worn comfort and a physical panel/sensor latency measurement remain open. At 90 Hz the reference
scene now locks close to 90 without a module wait; the heavier scene's measured CPU/GPU work and
compositor throttling limit it to about 33. Deriving 80-Hz budgets does not establish 80-Hz FPS.
Independent review/approval and shared-document integration remain with Claude/user before merge.

Shared-document/decision update to the initial Q proposals: replace serial completion pacing with
render-side Submit/Wait, nonblocking explicit prediction and measured pipeline feedback; add the
Lua trust boundary, native quit ownership, paused render poll, connection-gated overlays, recenter,
consumed-camera regression and the four long-run timing tables. Keep all limitations above explicit.

# 0174: VR measurements and flat controls

Accepted for the V2/V3 branch on 2026-11-11, task Q. Refines the evidence requirements of
[0172](0172-vr-combined-acceptance-and-evidence.md).

At the actual current Index refresh (do not change SteamVR settings), compare gm_construct
and Modern House at 1280x720 and 3840x2160 with one preset and visible hands. Compare the same
scene with/without a small world object centred 0.2 m from the head. Verify it in the images.
Use an explicit steady sample window after the first capture and before the HUD-change capture.
Retain rejected runs and machine process/GPU inventories. Submitted eye pairs per elapsed second,
compositor presents/reprojections/drops, covered timestamp brackets per GPU pass, elapsed GPU span,
render-thread CPU and game-thread CPU are distinct quantities; never label their sum a frame time.

A development-only clock helper reads GetThreadTimes and QueryThreadCycleTime on the game
thread. Exclusive registry-call attribution subtracts nested callbacks. Report CPU accounting
quantization, wrapper/clock overhead and all-active captures rather than pretending microsecond
precision or equating SysTime elapsed time with CPU. The helper is never packaged. With VR off
there is no module registry/callback to attribute: count zero callbacks, and use whole-game
alternating controls to test measurable cost. Count actual nlvr sends by type in both realms,
retaining the wall interval and engine net.BytesWritten values; these are not NIC traffic.

Flat parity uses five plus five alternating launches against the exact GMA identified by main's
publication SHA-256, the same map/pose/window/settings, with no VR load. Preserve each launch's
frame-interval median and start-to-map time, full hooks/timers/receiver inventories and paired
screenshot differences. State natural variation and image noise explicitly. The final screenshot
gets three seconds with the fixed camera still installed before cleanup. A missing/failed launch
does not become a pass through aggregation. The dormant server stub receiver is the sole expected
new off-state server receiver; session hooks/timers/client receiver/global must be absent.

Before these controls run, set practical rejection bounds: an increase in the median of five
frame medians above max(0.25 ms, 5%), median launch-to-map above max(1 s, 10%), or a paired RGB
mean difference above the largest published-to-published difference plus 1/255 fails. Preserve
the raw numbers and full inventory differences; passing those bounds does not prove exact zero
overhead or eliminate the need to review the screenshots.

The manual --look command must actually run under a fresh package-free venv. It takes the normal
locks and restoration path, imports no Pillow and must finish cleanly through nl_vr_demo_done.
Testing only an import or mocking the dependency preflight is insufficient evidence.

The controlled warp comparison keeps visible wrists 1.1 m forward at eye height so forearms
do not contaminate the far-depth control. The near cube uses actual visible mesh vertices to
place its front at 0.2 m; record both that front and its farther centre, then verify the GPU
minimum-depth capture. This supersedes the prototype centre-at-0.2-m placement.

Post-game collection uses a same-volume atomic rename of the owned native capture directory
to its retained location, with resolved-path/link/existing-destination guards. The earlier
byte copy held the PoC lock for minutes after game exit on this machine. This changes only
collection IO, retaining all raw evidence unchanged and the normal rollback checks.

The listen server shares the process, so CPU attribution also wraps its module registry with
the same read-only clocks. Retain server ticks and exact elapsed interval separately; report
CPU per server tick and, where useful, the explicitly converted client-frame equivalent.
Direct receiver work outside the registry remains unattributed. This fills the server-side
measurement rather than treating client module totals as all game-thread VR work.

The full off-state inventory check also rejects unexplained non-nlvr callbacks. Compare each
candidate with the published controls' common set and union, retaining both paired differences
and observed published variation. The patcher's retry suffix encodes its patch ID; preserve
the exact name (including all-digit hex IDs), rather than treating it as a random instance.
One-shot retries seen both present and absent in the published controls are measured baseline
variation, not a new permanent VR timer. No numeric performance/image tolerance is relaxed.

Client callback CPU uses distinct game FrameNumber values observed at active PostRender,
retaining raw PostRender counts and source-frame endpoints too. Legacy receipts keep their
PostRender-only label. Native eye-pair counters can differ during menu phases and are not
silently substituted as the callback denominator.

The disk filled during Q's late capture. Keep that failure and its incomplete raw files;
recover the PoC from the preserved originals under both locks and verify stock/protected hashes.
Completed capture files may use transparent NTFS compression only with full before/after
size/SHA-256 verification; their logical bytes and paths stay unchanged. No user data is removed.
The driver now reserves 8 GiB on the evidence volume (12 for the combined fixture), checks again
after waiting, and fsyncs a shared unfinished-transaction marker before preserving PoC. Only
matching verified restoration clears it; another session fails closed until recovery.

A failed installation that never reached the game command may use a fresh, explicitly selected
attempt folder without changing the actual alternating launch sequence. Keep the original
failed preparation and parity result. Any attempted game, even a failed one, cannot be replaced
inside the batch. All ten selected launched games and all original numeric limits remain required.

The NPC punch fixture now lasts 200 ms at 4 m/s: the former compressed 75-ms swing could finish
before the physical proxy reached the NPC hull. The unchanged damage criterion still requires
the real engine hit and 25-damage cap; no health value is assigned to produce a pass.

Quiet render-thread CPU reanalysis uses selected per-profile GetThreadTimes brackets, preserving
the earlier mean of cumulative averages separately. The raw captures and original measurements
stay retained, and the GPU/pass/rate window is unchanged.

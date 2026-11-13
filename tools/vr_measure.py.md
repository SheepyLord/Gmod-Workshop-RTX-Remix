# vr_measure.py

An empty Lua message table can decode as an empty JSON array. accounting_checks treats that as a
missing dynamic-state witness (false), never an exception or successful traffic. The separate
stationary cache control scopes that one witness explicitly; combined accounting still requires it.

Measures the complete candidate through tools/vr_session.py, preserving every standard role,
counter, screenshot, lifecycle and rollback assertion. Run `py -3 tools/vr_measure.py --package
out/dist/candidate.gma --evidence out/vr/v2q/new-measurement --map gm_construct|modern_house
--window 1280x720|3840x2160 [--near]`. Requires the built read-only clock helper from
tools/vr_measure_build.ps1, Pillow and the real Index. Both shared locks are held; no SteamVR
setting (including refresh) is changed. Uses the cached Modern House item 3495468649; no download.

Forty-five active seconds, same fixed preset and visible hands; the explicitly reported steady
window is samples at 10..35 seconds after running, after the first capture and before the HUD
change. Counts real submitted eye pairs over elapsed wall seconds, compositor presents/drops/
reprojections, covered GPU timestamp brackets by pass, elapsed GPU span and render-thread CPU.
Those are separate quantities. Hands remain visible at a fixed wrist pose 1.1 m forward,
0.22 m to each side, at eye height, tilted up 35 degrees. This keeps the forearms out of the
close-range control. `--near` adds a 0.1-scale world cube whose visible mesh front is commanded
0.2 m from the head: the actual mesh minimum X determines its centre, rather than treating padded
model bounds or the cube centre as surface depth. The image/GPU minimum-depth capture must
verify visibility and actual near/far depth. The four map/window comparisons use the same pose.

All-active callback CPU attribution uses exclusive GetThreadTimes deltas, plus cycles and wall
time. Windows CPU accounting is quantized; wrapper/clock overhead and capture intervals remain
included and are reported as such. Off has no module registry/callbacks. Client/server nlvr sends
are counted by type with net.BytesWritten engine bytes; these are not NIC packet/byte counts.
Outputs normal driver evidence plus measurements.json, profiler records and exact generated
sources/arguments. Invokes only the user's authorised field-game quit helper when needed and
records it. No package/native input, field file, loader source or Steam setting is edited.
Exit 0 only on complete driver success plus enough covered steady samples/profiles, otherwise
nonzero. Failed records remain. Test scratch and all output stay under out.

Normal map/window/near GPU comparisons leave the callback profiler off. A read-only cumulative
game-thread CPU sample once per second remains; --profile-modules explicitly adds the full
callback clocks/network observer when wanted. Required per-module CPU/network data come from
the combined acceptance with --inspect-dll, separately from these unprofiled GPU comparisons.
Private fixture staging avoids long console transport. Captured frame_minimum_depth.f32 values
are decoded with the actual recorded units/metre; this is axial view depth, not Euclidean range.

Scenario acceptance also requires the observed refresh remain 90 Hz and the neutral GPU minimum
verify a front at 0.195..0.205 m for --near, or no surface within 0.4 m for its far control.
Neither a commanded cube position nor an assumed headset setting substitutes for that receipt.

Accounting keeps Q-server-profile records with their own elapsed time and tick denominator;
these are exclusive server registry callbacks, separate from the client frame totals.
accounting_checks requires real callbacks in both realms, observed sync/state sends and an
off-state registry witness; missing data fails instead of being reported as measured zero.
Client callback CPU divides by distinct active game frames, retaining raw PostRender count
and source-frame endpoints separately; legacy PostRender-only receipts retain their old label.

Quiet render-thread CPU uses each selected profile's render_thread_cpu_ms (quantized
GetThreadTimes). The mean of the runtime's cumulative CPU averages is retained in a separately
named field; it is not silently treated as a quiet-window per-profile measurement.


Armed review controls: --weapon weapon_pistol|weapon_smg1|weapon_physgun selects before Start, never fires or creates/removes world targets. Recorded Index components supply natural holding frames with controllers off. Actual sampled weapon class/model and increasing draw count are required throughout the 10..35-second window; measurements.json records the exact package SHA. Output is concise; detailed CPU/GPU quantities remain in the receipt.

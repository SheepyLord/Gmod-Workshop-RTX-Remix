# vr_move_session.py

Task L acceptance driver. Example:
`py -3 companion/tests/vr_move_session.py --case movement --package out/dist/gmod-rtx-remix-0.0.0-v2l.1.gma --evidence out/vr/v2l/index-movement --seconds 50`.
Use `--case teleport --seconds 40` for blink/shift, mantle, invalid destination and zero-vignette fade.
Use `--case combined --seconds 85` to cover movement and teleport in one short PoC/Index session.
Use `--case latency --simulate --seconds 22` for per-rendered-frame camera measurements: two-second
side translations at 0.5 and 1.5 m/s, three seconds of 2 Hz +/-5 cm sway, then a head-roll interval.
The 50 Hz source samples interpolate natively at rendered-frame times and fit the 1 MiB timeline bound.
`--case followup --seconds 105` runs the normal 36 checks first, then the same latency/roll
measurements on the Index in one session. Linear/held sections need only boundary samples;
the sway keeps its 50 Hz samples, staying under the native 1 MiB cap.
Its separate latency probe records actual CalcView returns without changing movement code.
`--case locomotion --simulate --seconds 22` measures 2 s walking, 1 s sprint and 2 s full-trigger
level noclip flight with a stationary head, including every server tick and the engine feet paths.
`--case allmotion --seconds 127` appends those locomotion intervals to the 36 movement checks
and head-translation tests, so a single Index run proves all three without repeated SDK sessions.
The generated final Exit check waits 0.5 seconds after native off before comparing live GPU
selectors: the transition callback may still expose the last VR frame. The first cycle's five
flat seconds independently demonstrate restoration. Selector differences remain fatal.
Other options pass through to `tools/vr_session.py`, including `--simulate` when N is integrated.
Movement with `--seconds 58` also teleports after walking/turning, for combined Index acceptance.
The movement sequence bends physically while virtual crouch is on to check continuous eye height.
Requires the standard driver's built bootstrap, package, Pillow and PoC dependencies; Index runs
also require SteamVR. Never changes SteamVR settings or ends SteamVR/other tasks' processes.

Uses the unchanged session driver's locks, preserve/restore, protected-file checks, normal quit,
with task label `VR-V2-L` in the exclusive lock's owner receipt,
and up to one hour waiting in 3-second intervals for the parallel task owners,
captures, standard acceptance and summary. Replaces only the generated probe's fixed-command
clear, appends L's client probe and injects its server fixture through acknowledged console stages.
Timeline/temporary files/evidence stay under repository `out/`. Offloads no production authority
to a stand-in. Fixtures, calibration and settings changes are restored before the standard Exit
checks. Server test props are removed and the whole PoC transaction is verified/rolled back.
Never uploads, publishes or writes the field install. Exit codes follow the standard driver.
The capture checker preserves all required eye/depth/mirror files and verifies the wrist's glyphs
at 769 x 257. It also decodes each extra bounded RGBA8 canvas and records its centre alpha and
green/red pixels in `L-capture-metrics.json`. V1's assumption that every overlay is a white-text
wrist does not apply to an intentionally black fade or coloured arc; no tool file is changed.
The original stock module/runtime package can be used until N/R are merged; no DLL import is needed.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

# VR-V1-Q: integration, the package part, and V1 on the Index

Read first: [VR-plan.md](VR-plan.md) (the design; its decisions table is binding; the V1 row is what must hold),
[VR-V1-plan.md](VR-V1-plan.md) (interfaces, rules for every task and for PoC and VR tests), the four tasks' reports
([A](VR-V1-A-report.md), [C](VR-V1-C-report.md), [D](VR-V1-D-report.md), [E](VR-V1-E-report.md): each ends with
what it leaves to you), [AGENTS.md](../../AGENTS.md). You are the implementer; Claude reviews. Your branch is
`vr-q` in `out\worktrees\vr-q`; it starts from `vr`, which holds the probe, the runtime's patches, the module, the
add-on and the page.

The pieces were built side by side against written interfaces and have never run together. Your task is to make
them one working thing, package it, and prove the V1 row on the user's Valve Index, with numbers.

## 1. Make the pieces meet

- `vr/native/include/rtxvr_api.h` and the header inside the runtime's patch must be byte-identical (apart from
  line ends): add a test to the gate that compares them (the patch file holds the header as added lines).
- The Lua side: what the page and the add-on call and read (`nlvr.*`, the fields of `nlvr.Info()`, the frame
  table) against what the module provides. Fix the side that is wrong; record each mismatch you found.
- The start and the pacing. Spike S3 found that under `mat_queue_mode 2` Lua's next `WaitGetPoses` can come
  before the render side submitted the previous frame (`VRCompositorError_AlreadySubmitted`, 139 failed eye
  calls in 6,436 frames); VR-C's driver cured it with a completion ticket (its report, "S3", says exactly how:
  wait for the previous output before `WaitGetPoses`, arm the next ticket after it, never hold a mutex while
  waiting, and install the view hooks when the module is ready rather than after a first traced VR frame).
  VR-D's module has its own version of that wait (a 25 ms bound, armed by `SetFrameCamera`) and returns nil from
  `BeginFrame` until the runtime reports RUNNING, with a 10 s deadline; the page starts the add-on when the
  state is "running". These were written apart: run the real sequence, make the three agree, and show that the
  start can neither deadlock nor lose frames, with SteamVR already running and with SteamVR not running (Start
  VR then starts it: the game must stay responsive meanwhile; measure its frame times during the start), and
  that a long run has no failed Submit.
- Frames without a path-traced scene (a map load, the menu before a map): nothing is submitted. The game must
  not stall on the pacing wait, and Exit VR must work from there. Say what the headset shows meanwhile.
- `fps_max` is on Garry's Mod's list of blocked console commands, so the add-on cannot raise it: when it is
  below the headset's refresh rate the page must say so and say what to type. For tests, set it on the command
  line and end the session as `poc_session.py` does (the PoC and the user's game share `config.cfg`).

## 2. The package part `vr`

A new part of the RTX package, modelled on `load-accelerator` (`tools/workshop.json`, `packages/README.md`,
[ADR 0140](../decisions/0140-the-load-accelerator.md)):

- The add-on `vr/addon` deployed as `garrysmod/addons/nlvr`, with `vr/input` inside it as `input/` (the action
  manifest and the bindings must be real files on disk: SteamVR reads them by path), the MIT `LICENSE`, and
  OpenVR's BSD-3-Clause licence beside the DLL's use (`third_party/openvr/LICENSE`).
- `garrysmod/lua/bin/gmcl_nlvr_win64.dll` and `garrysmod/lua/bin/openvr_api.dll` (the package format allows DLLs
  there: [PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md), `root_files`). No loader change: if the format cannot carry
  something, stop and say so.
- `packages/vr/`: the two DLLs through `tools\inputs.py import` (xz in Git LFS), `files.json`, a `README.md`;
  `tools/ci/pins.json`: the module as a `repository_builds` entry
  ([ADR 0126](../decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)), `openvr` no longer
  `staged`; the CI scripts under `tools/ci` so that `package.yml` could build the part (do not start any
  workflow); the part's row in `packages/README.md`.
- **The runtime DLL, imported once**: when the runtime's patches are final, `runtime\build_runtime.ps1` builds and
  imports `d3d9.dll` into `packages\runtime` and records what it was built from (the pending patches become
  packaged). One import for this hand-over; experiments use `-NoImport` builds under `out\`. The runtime clone's
  branch `vr` is at `62736bda` (patches 0042 to 0059; VR-C's last `-NoImport` DLL is 418,332,160 bytes, SHA-256
  `73adc01d4ad83c50b48ccc1457c8cc7457916bec668731de719925fdd6779a8c`, in `_CompRelease_x64\src\d3d9`). VR-C has
  finished, so the clone is yours.
- `python tools\build_package.py` builds the whole package locally (it uploads nothing). Nothing is published,
  and nothing here goes to `main`.

## 3. `tools/vr_session.py`

The VR test driver on top of [`tools/poc_session.py`](../../tools/poc_session.py.md), with its `.md` and tests:
both locks (the PoC lock and `out\vr\vr.lock` in the main checkout), the local package installed with a snapshot
and rolled back afterwards, a timeline for the module's test mode, Start VR through the page's command, waiting
for "running", captures at chosen moments (`nlvr.Capture`: eyes, centre, depth, overlays, mirror), samples of
`nlvr.Info()` (the compositor's frame timing and cumulative stats, the runtime's status and GPU times), Exit VR,
flat screenshots and a dump of the console variables before Start and after Exit, the relevant lines of SteamVR's
own logs, a summary as JSON. It leaves SteamVR running and changes none of its settings.

## 4. V1 on the Index: each line with its evidence

1. Start VR from the page shows the path-traced view in the headset: saved eye images at several scripted head
   poses follow the head (turning the head by an angle moves the picture as the geometry says; a near object
   shifts between the eyes the right way; nothing mirrored, upside down or swapped), and no flat HUD in them.
2. The compositor receives every frame: several minutes of frame timing and cumulative stats, the Submit errors
   (none expected after the pacing wait), presents, dropped and reprojected frames.
3. The desktop window mirrors the left eye, with the game's own 2D on top.
4. The wrist HUD overlay: SteamVR reports it visible, it sits on the (scripted) left controller, its saved
   image shows the real health, armour and ammo, and it changes when they change.
5. Exit VR returns to the flat game with the player's settings: the console variables before Start and after
   Exit are the same, flat screenshots before and after match, frame times are back, `openvr_api.dll` is no
   longer loaded, no hook or timer of the add-on is left; Start and Exit twice in one session; quitting the game
   while in VR leaves no setting changed.
6. The failures a player can meet say what to do: SteamVR not installed (cannot be made here: test offline), the
   module or the runtime's VR output missing, VRMod or gVRMod active, another server.
7. **With VR off nothing changes.** The published runtime against the new one in the PoC, flat: the usual
   screenshots (same map, pose and settings; a fixed clear sky), frame times in alternating repeats (three pairs
   at least; VR-C's first pair was 7.94 against 8.26 ms median and proves nothing yet), start-up time, and the
   loaded modules (no `openvr_api.dll`). State exactly what the new runtime does differently at start-up (VR-C's
   report: five Vulkan extension names enabled at device creation) and show that it costs nothing.
8. **The cost in VR:** GPU time by pass, the CPU frame, and the frame rate at the Index's recommended size with the
   one fixed preset, on gm_construct and on one heavier map. VR-C's numbers on gm_construct (its report, "Fine
   times and the limiting stage"): DLSS Performance with Ray Reconstruction at render scale 1 (eyes 2468 x 2740,
   centre 3072 x 2752, traced at 1536 x 1376): 9.66 ms of GPU work a frame (path tracing 6.29, upscaling 2.16, both
   warps 0.11), 44.9 FPS at 90 Hz with the completion wait, 101.6 FPS without pacing; the game thread works 4.5 ms,
   waits 9.1 ms for the render side and 8.6 ms in `WaitGetPoses`. So the frame rate is bound by the serial
   hand-over, not by the GPU. Reproduce those numbers with the real module and add-on, with the runtime's fine
   split (`timings.json` beside each capture, the periodic profile lines in the log).
   **The preset.** The page's `nl_vr_render_scale` defaults to 0.7 (0.5 at most with the GPU warning) and VR-C
   measured at 1: the two were chosen apart. V1 needs one fixed, sensible preset: measure render scale 1, 0.85
   and 0.7 with the real module (frame rate, GPU work, the share of reprojected frames), settle the default from
   the numbers, make the page, the module and the runtime agree on it, and say why. The
   headset is at 90 Hz and its refresh rate is a SteamVR setting, which is not changed: measure at 90 Hz and give
   the 80 Hz figure from the measured times against a 12.5 ms frame (say plainly that it is derived). If the
   user switches the headset to 80 Hz while you work (check the rate at each run), measure it then.

## 5. The way for the user to look

The user will put the headset on. Give exact commands, tested, in your report: put the V1 build into the PoC (a
snapshot first), start the game, start VR from the page, and roll everything back afterwards. Say what they
should expect to see and what V1 does not do yet (no hands, no movement by controller, no menus in VR). VR-A
found that SteamVR quit at 04:02 on 2026-11-10 right after two launches of Garry's Mod through Steam had waited
on a Steam dialog: find out what Steam does when the game is started while SteamVR runs (from the PoC's own
executable, as the driver starts it, and as far as its logs tell for a start from the Steam library) and tell
the user what to choose.

## 6. Documents and the gate

Your text for the shared documents goes in your report (Claude writes them at the end): the decision records
(the runtime's VR output and the phase-1 warp; the module owning OpenVR, poses matched by the camera, frames paced
by completion; VR UI through SteamVR overlays fed from exact-size render targets; SteamVR's Vulkan extensions
enabled at device creation; the fixed V1 preset), CHANGELOG, COMPONENTS, ROADMAP, RESEARCH (S1-S8 with the
numbers of the four reports and yours), TESTING, `packages/README.md`. `tools\test.ps1 -Config Release` must pass
in `out\worktrees\vr-q`.

## Rules that matter most here

- "Rules for every task" and "Rules for PoC and VR tests" of the work plan, all of them: the two locks, SteamVR
  never quit and its settings never changed, the user's files, the crash prompt, no archived console variable
  left changed, the loader's update reminder removed from screenshots by Lua.
- You may change any VR piece to make them fit (the module, the add-on, the page, and the runtime through new
  patches in the runtime clone's branch `vr`, exported one at a time), and nothing else in the repository beyond
  what the package part needs. No loader change. No push, no merge, no publish, no workflow.
- Mind the disk and Git LFS: one runtime import, one import of each VR DLL; delete snapshots and DLL copies
  under `out\` once a rollback is verified (if a deletion is refused, leave it and say where it is).

## Done

The V1 row holds on the Index with the evidence above under `out\vr\q\` in the main checkout; the package builds
locally with the `vr` part; the gate passes; `docs/handover/VR-V1-Q-report.md` says what works and what does not,
every measurement, every mismatch found between the pieces and how it was settled, what in the plan turned out
wrong, the commands for the user, and your text for the shared documents.

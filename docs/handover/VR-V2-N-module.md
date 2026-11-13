# VR-V2-N: the module for V2 and V3

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it: its interface 8 is what you build, its rules are yours.
You know the module from V1 (VR-V1-D); since then the second review changed it (the native quit, the deferred IPD,
the Lua boundary of ADR 0150): read the code as it is on `main`, and
[VR-V1-Q-runtime-review-report.md](VR-V1-Q-runtime-review-report.md).

Your branch is `v2n`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2n`.

## What to build

1. **Simulated sessions** (interface 8, first row). The point: the feature tasks (hands, movement, menus, physics)
   test their Lua in PoC sessions without SteamVR and without the VR lock, as soon as possible. No `openvr_api.dll`
   is loaded; the Index's description (eyes as `GetProjectionRaw` and `GetEyeToHeadTransform` return them, IPD,
   recommended size, refresh) comes from a JSON file in the test root, recorded from V1's measurements (put the
   recorded file in the repository under `vr/native/sim/` and have the driver copy it); poses and actions come from
   the timeline; frames are paced by a timer at the refresh rate; overlays are kept in the module with their own
   handle numbers, placements and visibility, and `OverlayInfo` reports them; the runtime starts with
   `RTXVR_START_NO_SUBMIT` and a null `getGenericInterface` (task R makes the runtime accept that; until it does,
   prove the module side with the fake runtime of your tests). Refused unless the launcher set the test root, like
   timelines (ADR 0150). `Info()` says `simulated = true`.
2. **SteamVR's keyboard**, **the binding UI**, **overlay sort order and colour**, **finger splay**, as the table
   says; keyboard events through `Events()`; all scriptable by the timeline.
3. **The window overlay source**: `nlvr.OverlayWindow(handle, enable)` calling the runtime's
   `rtxvr_SetOverlayWindow` (interface 9), found by name in `d3d9.dll`; declare it privately in the module (the
   shared header is task R's until integration). With a runtime that lacks it, the call returns false and a message.
4. **The timeline**: every action type (booleans, axes, grip force, trigger value, curls, splay), keyboard events,
   with interpolation of axes and curls between steps where V1 interpolates poses. Document the format in
   `vr/native/README.md` with an example a feature task can copy.
5. **The driver** (`tools/vr_session.py` and its `.md` and tests): `--simulate` (no VR lock, no SteamVR, the module's
   simulated session; everything else as a normal run, captures included) and `--window WxH` (the game window's size,
   default 1280x720). Keep every other behaviour.

## Files you may change

`vr/native/**`, `vr/input/**` (only if an action must be added; say why), `tools/vr_session.py`,
`tools/vr_session.py.md`, `tools/tests/test_vr_session.py`, decision record **0161** (simulated sessions for tests)
with its line in `docs/decisions/README.md`, and your report. Not the shared header
`vr/native/include/rtxvr_api.h` (task R's).

## Proof

- C++ tests against the fake OpenVR and the fake runtime for every new function and for the simulated session
  (start, frames at the refresh rate, poses and actions from a timeline, overlays, keyboard events, stop, refusal
  without the test root); the input checker for any manifest change.
- One simulated PoC session on gm_construct with the V1 package plus your module (rebuild the package from your
  branch): the add-on runs, frames are produced and captured, Exit is clean, no `openvr_api.dll` in the module list.
  The runtime of `main` may refuse a null interface; then record exactly what it does, and prove the rest with the
  fake runtime.
- One session on the Index with your module (both locks): V1's acceptance still holds; the keyboard opens and closes
  (scripted), the binding UI call returns.

## Report

`docs/handover/VR-V2-N-report.md`: what you built, the timeline format with an example, the tests and evidence, what
is open, your text for the shared documents. `tools\test.ps1 -Config Release` passing in your worktree.

# A ragdoll's MMD physics starting far from the model (report)

Claude, 2026-11-25, from `main` at `50f36ada`, in a cloud container without Windows or the game; the Windows build,
the tests there and the PoC check were made on the user's machine. Package only: the Model Hotloader's natives; no loader (`winmm.dll`), runtime or
Lua change. Decision: [ADR 0266](../decisions/0266-a-body-without-a-bone-starts-with-the-character.md).
Facts: [RESEARCH.md](../RESEARCH.md), "MMD bodies without a bone under a ragdoll".

## The task

The user's report of 2026-11-25: "Investigate a bug, the ragdoll's mmd physics, when spawn or reset, started up at an
unexpected position far away from the model", with the PMX of the character it happened to (the user's own model, not in
this repository). Find the cause, with evidence, and propose a fix.

## Cause

A Model Hotloader ragdoll's MMD physics (the natives' `Secondary`: nanoem and Bullet) runs in the instance frame, which
for a client carrier is the map's origin: the carrier is created without a position, so its `placement` is the
identity. At every reset, `Secondary::follow(true, skin)` puts each rigid body at `skin[bone] * initial`, its PMX rest
transform carried by its bone. **A PMX body may name no bone**, and for those the natives used `initial` alone: the
body's rest place on a model standing at the map's origin. So the first pose after a spawn, Reset physics
(`Instance::reset()` builds a new `Secondary`), a teleport of more than 128 units and a quality mode switch put every
such body at the map's origin. Their joints then pulled them back to the character over a quarter to half a second,
dragging the chains they link across the map: what the user saw. A follow-bone body without a bone would never have
come back: it was drawn at the origin every frame.

The reported character (Character A below, a placeholder for the user's imported test character) has 68 such bodies:
60 skirt lattice bodies (the cross-links between its skirt chains) and 8 chest helpers. All 68 are dynamic and reach a
body with a bone through their joints.

## Evidence

The natives' runtime (`mmd_runtime`: model, physics, secondary physics, rig; nanoem and Bullet at the locked commits
with `bootstrap.py`'s and `patch-bullet-threading.py`'s patches) was built from `packages/model-hotloader/source/mmdhl`
with GCC 13 on Linux, with a stub for the Vulkan backend, and driven like a client carrier: `backend source`, `presentationDriven`, a Source pose palette from the
fitted rig placed at Source (1500, -900, 64), 1,750 units from the origin, then submitted frame by frame
(`submitPresentationPose`, `stepSource`), with `Instance::reset()` for Reset physics. Distances are Source units from
the ragdoll's pelvis; the default backend `cpu_mt_v2` (`reference` within a unit of it).

| Character A, on Linux | first frame | frame 1 | frame 5 | frame 15 | frame 30 | frame 120 |
|---|---|---|---|---|---|---|
| bodies without a bone, mean / max, before | 1,476 / 1,642 | 1,211 / 1,373 | 528 / 606 | 51 / 62 | 5.4 / 9.1 | 6.8 / 10.1 |
| bodies with a bone, dynamic, max, before | 113 | 139 | 113 | 43 | 43 | 43 |
| farthest drawn vertex, before | 45.6 | 57.9 | 123.8 (44 beyond 120) | 45.6 | 45.6 | 45.6 |
| bodies without a bone, mean / max, after | 7.4 / 10.2 | 7.4 / 10.3 | 7.6 / 10.6 | 7.7 / 10.7 | 7.7 / 10.7 | 7.7 / 10.7 |
| bodies with a bone, dynamic, max, after | 43.0 | 43.1 | 43.3 | 43.4 | 43.4 | 43.4 |
| farthest drawn vertex, after | 45.6 | 45.6 | 45.6 | 45.6 | 45.6 | 45.6 |

Reset physics gave the same numbers as the spawn, before and after. The follow-bone bodies were where they belong
(31.5 at most) in both.

## The fix

`source/boneless-bodies.patch` (applied after `install-priority.patch`; listed in
[Source.md](../../packages/model-hotloader/source/Source.md)):

- `native/secondary.hpp`, `secondary.cpp`: `Secondary::buildFrames`, run when the physics is built, gives each body a
  frame bone: its own; for a body without a bone, the bone of the nearest body with one through the authored joints
  (shortest paths from all boned bodies at once over rest distances, as `buildAttachments` finds anchors), else the
  Source root (the rig's bone 0, the pelvis), as the Hotloader does for control roots nothing poses (its issue 6). A
  body the world holds through a joint keeps none and stays as before. `animatedPose(body, skin)` (`skin[frame] *
  initial`) replaces the old expression in the reset (`follow`), the follow-bone bodies and anchors of the
  presentation (`present`, `presentAsync`, `readSolved`, `buildAttachments`) and the diagnostics.
- `native/secondary_quality.cpp`: the same in the lightweight mode (`stepSimplified`), the quality blend and
  `resumeQualityPose`.
- At rest nothing changes: the skinning transforms are the identity, so a body starts at `initial` as before. A body
  without a bone keeps its rest offset from the body it is jointed to, so every joint starts at its rest length.

## Tests

- New: `tests/boneless_body_tests.cpp`, CTest `secondary_boneless_bodies`, with `tests/fixtures/native-boneless.pmx`
  (`scripts/fixtures.py`: dynamic bodies without a bone beside an 8-link hair chain and on the head, and a follow-bone
  body without a bone; the other fixtures come out byte for byte as before). For `reference` and `cpu_mt_v2`, a
  character lying on its back, turned and 3,000 units from the origin must start every body where the same start at
  the origin puts it, moved with the character (within 1 unit), and every joint within 0.05 PMX units of its limits,
  at the first pose, at Reset physics and after a 2,000-unit teleport; a second after the first pose its follow-bone
  body without a bone must ride on its head (within 0.01). **Before the fix it fails**: on Linux, with every check
  run, 20 of its 21 failed on both backends: bodies without a bone 2,941 units from their place (1,799 after the
  teleport), bodies with a bone 292 (dragged in the first step), a joint 770 PMX units out, the follow-bone body 2,941
  units away a second later. **After it all 21 pass**: every body within 0.061 units (one step's sag), joints within
  0.0073 PMX units, the follow-bone body exactly on the head. (On Windows, below, the test as committed stops at its
  first failed check.)
- The neighbouring native tests, built the same way and run with their CTest arguments, all pass after the change
  (24 runs; 25 with the new test): `secondary_motion`, `secondary_async`, `adaptive_physics_and_materials`, `adaptive_physics_nan_tails`,
  `presentation_timing`, `presentation_timing_control`, `secondary_gravity_buoyancy`, `secondary_projection`,
  `secondary_projection_unaffected`, `secondary_projection_mass_ratio`, `secondary_midphase`, `secondary_heavy_chain`,
  `secondary_stretch`, `secondary_stretch_ground`, `secondary_projection_ground`, `gpu_skinning` and its three variants
  (the Vulkan path stubbed), `flashlight_overlaps`, `backface_twins`, `secondary_broadphase`,
  `animated_carriers_and_sharing`, `torso`.
- `tools/check_repo.py` passes, and `tools/inputs.py verify` finds no problem. The Python tests (`python -m unittest
  discover -s tests` in `tools`, `tools/gmapack` and `tools/steam`) give the same result on Linux with and without the
  change: `tools` has the same 31 failures on both, nearly all Windows-only modules (`ctypes.WinDLL`, `msvcrt`,
  `_winapi`); `gmapack` and `steam` pass.
- The Linux build differs from the shipped one in its
  compiler and in the stubbed Vulkan backend (`gpu_vulkan` falls back to `cpu_mt_v2` without a device, as it does on a
  machine without one).

## On Windows

The main thread, on the user's machine (Windows 11, Visual Studio 2022's MSVC), on the local branch `boneless-bodies`
(worktree `out\worktrees\bnl`, from `main` at `50f36ada`). A first version of this change went to GitHub as a pull
request whose notes named the user's character; it was withdrawn, and the change came back as two patches, which
applied cleanly. These notes call the character Character A and leave out its body names.

- **One fix for MSVC.** The test named its placement `far`, which `<windows.h>` defines as an empty macro, so MSVC
  stopped at `error C2059`. It is `away` now; nothing else in the test changed. `boneless-bodies.patch` was written
  again from the change (27,970 bytes) and turns `main`'s `mmdhl/` into the part's, file for file.
- **The fixture.** `scripts/fixtures.py`, run in a copy under `out\`, writes `native-boneless.pmx` at 9,793 bytes
  with SHA-256 `986ea8ad...`, as on Linux, and the 61 other fixtures byte for byte as stored.
- **The natives.** `tools\ci\build_hotloader.ps1` with the patched source and the add-on's pinned dependencies
  (`-Vendor`, nothing downloaded; 4.5 minutes with `-Jobs 16`): release 2.3.1, build `50f36ada42f2-20261125T074901Z`,
  `gmcl_mmdhl_win64.dll` 2,936,320 bytes, `gmsv_mmdhl_win64.dll` 1,910,272, `mmdhl_runtime_win64.dll` 10,994,688 and
  `mmdhl_worker.exe` 4,257,792, with `native_policy.lua` and `mmdhl-native-release.json`. They were imported into the
  part with the eight changed sources and the fixture (`tools\inputs.py import model-hotloader --file ...`, 15 files,
  their origins in `files.json` written with `<repo>`); `inputs.py verify` finds no problem.
- **The Hotloader's CTest**, every target built in that work folder: 38 of 39 pass, among them
  `secondary_boneless_bodies` with all 21 checks (every body within 0.061 units of its place, joints within 0.0053
  PMX units, the follow-bone body on the head). The 39th, `character_import_worker`, cannot run from this repository's
  copy of the source, which has never held its `scripts/test-character-import.py`; it fails the same way without the
  change.
- **The old code** (`main`'s three native files put back and the test rebuilt): the test fails at its first check on
  the start, as on Linux: bodies without a bone 2,941 units from their place, bodies with a bone 292, a joint 770 PMX
  units out of its limits.
- **Character A**, the user's PMX read where it lies (the field library's asset is the same file), with a scratch
  harness built like the test (`out\hlb\harness`): placed at Source (1500, -900, 64) turned 0.6 rad, 120 frames from
  the first pose, then Reset physics, then a 2,000-unit teleport, with both CPU backends (`cpu_mt_v2` below;
  `reference` within 2 units):

  | Character A, on Windows | first frame | frame 1 | frame 5 | frame 15 | frame 30 | frame 120 |
  |---|---|---|---|---|---|---|
  | bodies without a bone, mean / max, before | 1,462 / 1,518 | 1,199 / 1,288 | 524 / 600 | 50 / 62 | 6.3 / 9.8 | 7.4 / 10.6 |
  | bodies with a bone, dynamic, max, before | 115 | 151 | 127 | 43 | 43 | 43 |
  | farthest drawn vertex, before | 45.6 | 56.1 | 147.4 (155 beyond 120) | 45.6 | 45.6 | 45.6 |
  | bodies without a bone, mean / max, after | 7.4 / 10.2 | 7.4 / 10.2 | 7.6 / 10.5 | 7.7 / 10.7 | 7.7 / 10.7 | 7.7 / 10.7 |
  | bodies with a bone, dynamic, max, after | 43.0 | 43.1 | 43.3 | 43.4 | 43.4 | 43.4 |
  | farthest drawn vertex, after | 45.6 | 45.6 | 45.6 | 45.6 | 45.6 | 45.6 |

  Reset physics repeated the spawn's numbers exactly, before and after; the teleport, to 1,030 units from the
  origin, started them 851 units away on average before (891 at most) and 7.4 (10.2) after. 155 of the character's
  76,876 drawn vertices were beyond 120 units at the fifth frame before; none after.
- **A character without such bodies**: Linlong, the Hotloader's own character (599 bodies, none without a bone),
  gives byte for byte the same harness output with the old and the new code.
- **In the PoC** (RTX 5090, 1920x1080, gm_construct, RTX on; the main checkout's `out/qa-poc/boneless-bodies`):
  `out\hlb\poc_bnl.py` copied Character A's asset, library entry, fit, names, terms and textures from the field
  library, and a scratch server add-on that spawns it and moves it, into the PoC, and removed them afterwards.
  `bnl_probe.lua` read every body's place from `mmdhl.native.GetDiagnostics` each frame for three seconds after each
  event: the spawn as a ragdoll 130 units in front of the player; Reset physics; a 300-unit move of the ragdoll by
  the server; the physics paused, the ragdoll moved 300 units, the physics resumed 1.5 s later
  (`SetSecondaryQuality`, as the physics LOD does); the spawn as an NPC; the NPC's Reset physics. The bodies without
  a bone, mean / max distance from the pelvis at the first frame, and the largest in three seconds:

  | Event | published `0.0.0-dev.20261124104734+42e4e1f8` | this change, three sessions |
  |---|---|---|
  | ragdoll spawn | 684 / 710, 713 (the character 813 from the origin) | 7 / 10, at most 16 |
  | Reset physics | 831 / 836, 836 | 7 / 10, at most 12 |
  | 300-unit move | 679 / 708, 708 | 7 / 10 (see below) |
  | paused, moved, resumed | 830 / 836, 836 | 7 / 10, at most 12 |
  | NPC spawn | 598 / 626, 626 (720 from the origin) | 7 / 10, at most 16 |
  | NPC Reset physics | 650 / 679, 679; its dynamic bodies with a bone dragged to 1,012 | 7 / 10, at most 11 |

  With the published package every event's bodies came back over 10 to 30 frames; with this change they start on
  the character. The server's 300-unit move reaches the client interpolated over a few frames, not always as one jump
  past the 128-unit teleport test: in one of the three sessions the bodies with a bone lagged up to 331 units behind
  the moving pelvis for a few frames and those without a bone 121, in the others up to 69 and 42; the published
  package's run lagged its bodies with a bone 90.
- **One crash in the PoC.** One of the four sessions with this change (`04-branch`) ended with an access violation
  (0xC0000005) about three seconds after the ragdoll's spawn, while the probe waited between events:
  `shaderapidx9.dll+0x94fe` reading address 0 under the Hotloader's client module, `mmd::executeItem`
  (`native/renderer.cpp:878`, `mesh->Draw` of the shared vertex cache's mesh). That is the drawing code, which this
  change does not touch; the physics code is in `mmdhl_runtime_win64.dll`, not on that stack. No earlier record has
  this signature. The other three sessions with this change, and both with the published package, quit normally; the
  user's field game ran on the same GPU throughout. Left open, to watch for.
- **The gate**, `tools\test.ps1 -Config Release` in the worktree: repo conventions OK, C++ 35 of 35, Python 2,236
  tests in `tools` (2 skipped), 29 in `gmapack` and 26 in `steam` (one skipped each), "All checks passed". The first
  run had one failure, `nl_exit_observer_integration` (the loader's exit observer, which this change does not touch);
  it passed alone six times and in the second run.

## Open

- None for the change: the user approved it on 2026-11-25 ("Merge and publish"); ADR 0266 is accepted and the branch
  merged into `main`.
- The PoC crash in the Hotloader's drawing (`mmd::executeItem`, `shaderapidx9.dll+0x94fe`), seen once in four
  sessions with this change: to watch for in later runs and field reports.

# A ragdoll's MMD physics starting far from the model (report)

Claude, 2026-11-25, on the branch `claude/project-thread-mhoszg` (from `main` at `50f36ada`), in a cloud container
without Windows or the game. Package only: the Model Hotloader's natives (source); no loader (`winmm.dll`), runtime or
Lua change. Decision: [ADR 0266](../decisions/0266-a-body-without-a-bone-starts-with-the-character.md) (proposed).
Facts: [RESEARCH.md](../RESEARCH.md), "MMD bodies without a bone under a ragdoll".

## The task

The user's report of 2026-11-25: "Investigate a bug, the ragdoll's mmd physics, when spawn or reset, started up at an
unexpected position far away from the model", with the PMX of a character, Susan (the user's own file, read from their
computer; not in this repository). Find the cause, with evidence, and propose a fix.

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

Susan has 68 such bodies: 60 skirt lattice bodies (`裾格*`, the cross-links between her skirt chains) and 8 chest
helpers (`左胸_*`, `右胸_*`). All 68 are dynamic and reach a body with a bone through their joints.

## Evidence

The natives' runtime (`mmd_runtime`: model, physics, secondary physics, rig; nanoem and Bullet at the locked commits
with `bootstrap.py`'s and `patch-bullet-threading.py`'s patches) was built from `packages/model-hotloader/source/mmdhl`
with GCC 13 on Linux, with a stub for the Vulkan backend, and driven like a client carrier: `backend source`, `presentationDriven`, a Source pose palette from the
fitted rig placed at Source (1500, -900, 64), 1,750 units from the origin, then submitted frame by frame
(`submitPresentationPose`, `stepSource`), with `Instance::reset()` for Reset physics. Distances are Source units from
the ragdoll's pelvis; the default backend `cpu_mt_v2` (`reference` within a unit of it).

| Susan | first frame | frame 1 | frame 5 | frame 15 | frame 30 | frame 120 |
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
  body without a bone must ride on its head (within 0.01). **Before the fix 20 of its 21 checks fail** on both
  backends: bodies without a bone 2,941 units from their place (1,799 after the teleport), bodies with a bone 292
  (dragged in the first step), a joint 770 PMX units out, the follow-bone body 2,941 units away a second later. **After
  it all 21 pass**: every body within 0.061 units (one step's sag), joints within 0.0073 PMX units, the follow-bone
  body exactly on the head.
- The neighbouring native tests, built the same way and run with their CTest arguments, all pass after the change
  (25 runs): `secondary_motion`, `secondary_async`, `adaptive_physics_and_materials`, `adaptive_physics_nan_tails`,
  `presentation_timing`, `presentation_timing_control`, `secondary_gravity_buoyancy`, `secondary_projection`,
  `secondary_projection_unaffected`, `secondary_projection_mass_ratio`, `secondary_midphase`, `secondary_heavy_chain`,
  `secondary_stretch`, `secondary_stretch_ground`, `secondary_projection_ground`, `gpu_skinning` and its three variants
  (the Vulkan path stubbed), `flashlight_overlaps`, `backface_twins`, `secondary_broadphase`,
  `animated_carriers_and_sharing`, `torso`.
- `tools/check_repo.py` passes, and `tools/inputs.py verify` finds no problem. The Python tests (`python -m unittest
  discover -s tests` in `tools`, `tools/gmapack` and `tools/steam`) give the same result on Linux with and without the
  change: `tools` has the same 31 failures on both, nearly all Windows-only modules (`ctypes.WinDLL`, `msvcrt`,
  `_winapi`); `gmapack` and `steam` pass.
- Not run here: the Windows build, `tools\test.ps1`, the PoC. The Linux build differs from the shipped one in its
  compiler and in the stubbed Vulkan backend (`gpu_vulkan` falls back to `cpu_mt_v2` without a device, as it does on a
  machine without one).

## Open items

1. **Store the new fixture.** This container's network policy refused Git LFS's upload (`lfs.github.com`), so the
   branch does not carry `tests/fixtures/native-boneless.pmx`. Copy `scripts/fixtures.py` to
   `out\fixtures\scripts\` and run it there (it writes every fixture under `out\fixtures\tests\fixtures\`), check
   that `native-boneless.pmx` is 9,793 bytes with SHA-256
   `986ea8adce6064c701192ee5784b61dd34654425e630c7267f328b53bbe1ed15`, then
   `python tools\inputs.py import model-hotloader --file out\fixtures\tests\fixtures\native-boneless.pmx=source/mmdhl/tests/fixtures/native-boneless.pmx`.
2. **Rebuild the natives on Windows** with `tools\ci\build_hotloader.ps1` (release 2.3.1), run the Hotloader's CTest
   there (`secondary_boneless_bodies` among them), and import the four natives, `native_policy.lua` and
   `mmdhl-native-release.json` with `tools\inputs.py`. Until then the package's natives in `bin/` are the old ones, and
   a commit on `main` publishes nothing new for this.
3. **Check it in the PoC** with Susan: spawn her as a ragdoll and as an NPC far from the map's origin, use Reset
   physics, and teleport her; the skirt and chest should start on her.
4. Then merge, and mark ADR 0266 accepted.

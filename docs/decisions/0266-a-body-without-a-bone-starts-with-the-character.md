# 0266: A rigid body without a bone starts with the character

- Status: Proposed 2026-11-25 (the user's report: "the ragdoll's mmd physics, when spawn or reset, started up at an
  unexpected position far away from the model", with a character's PMX). It becomes accepted when the natives rebuilt
  from it on Windows pass the Hotloader's tests and the PoC check with that character, and the user approves it.
- Package only: the Model Hotloader's natives (`source/boneless-bodies.patch`: `native/secondary.hpp`, `secondary.cpp`,
  `secondary_quality.cpp`, a C++ test and its generated fixture). No loader (`winmm.dll`), runtime or Lua change.
- Facts: [RESEARCH.md](../RESEARCH.md), "MMD bodies without a bone under a ragdoll"; report:
  [boneless-bodies-report.md](../handover/boneless-bodies-report.md).

## Context

A Model Hotloader ragdoll or NPC drives its MMD physics (the "secondary" physics: nanoem's Bullet world in the natives)
from its Source skeleton. That world is the instance frame: the PMX's axes and units, placed in the map by the
instance's `placement`. A client carrier is created without a position (`mmd_hotloader/lua/mmdhl/instances.lua`), so
its placement is the identity and the instance frame's origin is the map's origin.

At every reset the natives put each rigid body where the animation has it: `Secondary::follow(true, skin)` sets
`skin[bone] * initial`, the body's rest transform carried by its bone's skinning transform. A reset happens at the
first pose after a spawn, on Reset physics (`Instance::reset()` builds a new `Secondary`), after a teleport of more than
128 units and when the quality mode switches. The same expression places the follow-bone bodies every frame and the
presentation's anchors.

PMX lets a rigid body name no bone (index -1). Such a body only links others through its joints: the lattice bodies
between a skirt's chains, a chest's helper bodies. For them the natives used `initial` alone, a place in the rest
space of a model that stands at the instance frame's origin, so **every reset put them at the map's origin**, as far
from the character as the character is from the origin. Their joints pulled them back across the map in a quarter to
half a second and dragged the chains they link out of the character on the way; a follow-bone body without a bone
would have stayed at the origin for good. The user's character has 68 such bodies (60 skirt lattice bodies, 8 chest
helpers): spawned 1,750 units from the origin, they started up to 1,642 units from its pelvis, its physics bodies
with a bone were dragged up to 139 units from it (43 at rest) and the drawn mesh stretched to 124 units.

The Hotloader fixed the same kind of fault for bones (issue 6 of its own repository): a control root nothing poses
rides with the Source root as if attached at rest (`evaluatePose` in `native/model.cpp`).

## Decision

1. **Each body without a bone gets a frame bone at load** (`Secondary::buildFrames`): the bone of the nearest body
   that has one, through the authored joints (shortest paths from every boned body at once, over the bodies' rest
   distances); a body that reaches none rides with the Source root (the rig's bone 0, the pelvis), as unposed bones
   do. A body with a bone keeps its own. A body the world holds through a joint (a PMX joint to body -1, and every
   body linked to it) stays where the world holds it, as before.
2. **Wherever the natives place a body from the animation, they use its frame**: `skin[frame] * initial`
   (`Secondary::animatedPose`): the reset (`follow`), the follow-bone bodies' presentation (`present`, `presentAsync`,
   `resumeQualityPose`), the presentation's anchors (`buildAttachments`, `readSolved`), the lightweight mode's display
   (`stepSimplified`), the quality blend and the diagnostics.
3. **Nothing changes at rest.** A body keeps its rest offset from the body it is jointed to, so every joint starts at
   its rest length; a model standing at the instance frame's origin in its rest pose (the skinning transforms are the
   identity) starts exactly as before.

## Consequences

- A ragdoll or NPC whose PMX has bodies without a bone starts its MMD physics on itself at a spawn, Reset physics and a
  teleport, anywhere in the map. The user's character: bodies without a bone at most 10.7 units from the pelvis from
  the first frame (1,642 before), its physics bodies with a bone at most 43 (139), no stretched vertex (44 beyond 120
  units at the fifth frame before, with the default backend), with both CPU backends.
- Characters without such bodies are unchanged: every body's frame is its own bone. The cost is one pass over the
  bodies and joints when the physics is built.
- The natives are rebuilt for Windows from this source (`tools\ci\build_hotloader.ps1`, release 2.3.1) and imported
  with `native_policy.lua` and `mmdhl-native-release.json`; the package workflow builds them from the same source.
- A body without a bone whose nearest boned body belongs to another limb than the one it looks attached to starts with
  that limb; its joints settle it in the first frames, as they did any joint error before.

## Alternatives considered

- **Every body without a bone with the Source root.** Simpler, but a skirt lattice body would start in the pelvis's
  frame while the skirt chains it links start in the legs' and the lower body's; on a ragdoll whose legs are apart its
  joints would start stretched.
- **The bone of the first body a joint names.** Depends on the order of the joints, and two bodies without a bone
  linked to each other (the reported character's chest helpers) need a walk anyway.
- **A placement for client carriers**, so the instance frame follows the character. Every user of instance-frame
  coordinates (collisions, the scene share, wind, water, the diagnostics) would change for the same result, and a
  teleport would still place these bodies at the old frame.
- **Leave them to the joints.** That is the fault: half a second of a skirt pulled across the map at every spawn and
  reset, and a follow-bone body that never comes.

# 0164: VR hands, fingers and ghosts

Accepted for task H on the V2/V3 branches, 2026-11-11, implementing the binding
[work plan](../handover/VR-V2V3-plan.md) and [hands brief](../handover/VR-V2-H-hands.md).
Milestone approval and integration remain separate.

Each physical hand has an opaque client-side copy of the local player's translated c_arms model,
including its registered skin/bodygroups. A model change replaces both copies. Missing model
registrations use GMod's citizen hands; a model lacking the requested wrist falls back per hand.
Left stays left when the dominant input role changes. The view-model pass stays suppressed.

The normal world opaque draw submits the models for path-traced lighting, shadows and reflections.
BuildBonePositions reads engine matrices before changing any, places the wrist at the final shown
pose and retains only its forearm/hand hierarchy. Other valid bones collapse at the elbow, with
finite zero scale rather than NaNs. The session's units/metre scales the model. Invalid named
bones never reach SetBoneMatrix. All models/callbacks die with the module.

Named ValveBiped/Bip01 finger joints tolerate missing phalanges. Curls bend three joints per
finger; optional splay fans proximal joints. Held-object grip curls override tracking and close
spread. Exponential smoothing uses a 35 ms time constant, advanced once per engine frame.

The priority-10 fallback sweeps a 3.5 cm radius brush-only hull from the head to a shoulder point
18 cm below and 18 cm to that side, then to the target wrist. This approximates an arm reaching
around the head without beginning with a shoulder inside a wall. Contact leaves 5 mm skin; a
start in solid conservatively keeps the wrist at the head. H changes shown position and blocked
only. P's later resolver owns entities and server proxy positions; target rays remain unchanged.
Climbing policy belongs to P/L rather than this fallback.

A valid blocked hand gets a faint static hand-shaped outline at its real target, facing the head.
An original contour is painted once per session into the reserved odd-sized transparent ghost
canvas, fed to SteamVR as UI (0.16 m wide, alpha 0.24). It is never traced geometry or a model in
desktop 2D. The setting hides ghosts without disabling collision; unblocked hands allocate none.
Exit/failure destroys them. Debug values expose model, bones, applied pose, distance, visibility
and resource work for the probe.

Interface facts were checked against Facepunch's
[hands documentation](https://wiki.facepunch.com/gmod/Using_Viewmodel_Hands),
[bone-matrix contract](https://wiki.facepunch.com/gmod/Entity:SetBoneMatrix) and
[SetupBones callback warning](https://wiki.facepunch.com/gmod/Entity:SetupBones).
No VRMod/gVRMod code, comments or pose tables are used.

Implementation evidence (task H's simulated PoC, 2026-11-11): a fresh citizen model reports
43 bones and exposes wrist 4 after SetupBones; discovery now initializes that cache first.
The ordinary opaque callback produced zero draws in this RTX path. Calling the same module
callback in PreDrawTranslucentRenderables produced 74 model/bone builds in one second and a
lit world capture. The module therefore draws its opaque world models at that stage, still
before translucent world geometry and never through the view-model or 2D paths. Both ValveBiped
wrists use the same bend basis; anatomical handedness lives in the model, with spread mirrored.

The next world capture measured an open finger joint 4.41 game units (11 cm) inside the wall
with a palm-only cast. The palm keeps its 3.5 cm half width; the hand cast now extends a further
14.5 cm along controller Forward (18 cm including the palm), with world-aligned conservative
bounds. If that extended shape starts in solid, it first tries a clear point 25 cm behind the
shoulder. This calibration keeps fingers outside the brush rather than stopping only the wrist.
Facepunch's [IsValidModel contract](https://wiki.facepunch.com/gmod/util.IsValidModel) also explains
the rejected Combine hands: a local model can be false merely because the server did not precache
it. Client model creation and wrist discovery now decide validity, without a server dependency.

Single-finger image inspection distinguishes the thumb's mirrored pitch/opposition from the
four fingers' shared yaw bend. The right thumb therefore uses negative pitch for a positive
curl, while both hands use positive finger yaw. The world wrist basis itself stays shared.

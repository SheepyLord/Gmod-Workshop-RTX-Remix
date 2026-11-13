# cl_hand_model.lua

Pure c_arms anatomical calibration, used by the hands module. `Measure(entity,bones)` reads the uncurled wrist and four proximal finger matrices . Its palm centre is halfway from wrist to mean knuckle; +X follows wrist-to-mean-knuckle geometry and +Z points across the hand toward the thumb. `Wrist(frame,shown,scale)` inverts this model-local frame to place the wrist under a shown palm. Missing or degenerate bones return nil for the existing fallback.

No hooks, SDK calls, files or resources. Measurements are Source units at 40 units/metre; placements scale with the session. No exit code.

The anatomical forward axis matches the native skeleton's wrist-to-mean-knuckle definition. Sequence zero may already flex phalanges; those directions do not define the palm frame.

CurlAxes measures each uncurled joint's anatomical flexion/spread axes in bone-local space. Apply uses them to flex into the palm with mirrored physical handedness and preserved spread; the original H Angles fallback remains for incomplete rigs. This helper is C-owned in core; H's existing cl_hands_pose.lua (discovery, smoothing, collision, outline) remains byte-identical to the task base.

Grip temporarily poses the new model at the owned weapon curls, computes the circumcentre of the middle finger's three joints, converts it to wrist-local authored units, then restores every manipulated joint/cache before drawing. Degenerate arcs retain the palm anchor. Circle is rigid-transform invariant and tested independently.

Line fits the four closed finger-arc centres; Fit maps that tube axis and centre to the model handle reference. Tips reads weighted distal mesh endpoints with the inverse bind matrix from util.GetModelMeshes, once per hand-model creation, so fingertip checks do not substitute wrist/bone origins for mesh tips.

When SDK skeletal data is available, ReferenceFrame and SkeletalMatrices retarget the wrist, joints and measured mesh endpoints to the SDK model-space poses. Finger lengths scale along each segment, preserving the selected model's cross section and positive scale. ModelConstraint applies only a bounded radial translation (at most 25 mm) to centre the reference grasp on the measured Index handle; raw diagnostic SDK markers are untouched. Degenerate/open arcs retain zero correction. Grip/reference state belongs to the caller, not this geometry helper. The controller frame helper is included once rather than compiled during every bone build.

## Review correction (2026-11-12)

Grasp calibration uses only GripLimit once; live Open/Fist/WithController circles never enter a weapon frame. Grasp displacement is bounded to 4 authored units (10 cm at 40 units/metre). SkeletalMatrices rebases articulation into wrist-local space and attaches it to the fixed reference wrist, then applies one model calibration. The recorded references' wrist roots differ by 8.92 mm, which must not slide the attached hand. Bone transverse frames use the stable knuckle hinge (thumb reference bend plane), with physical handedness separated from the sign used to drive a curl; the palm-normal projection is superseded. StoreSample reuses numeric arrays, detects unchanged poses and preserves good data on failed reads.

ModelConstraint is now independent of its sample argument. Only valid recognized Index component frames receive the fixed translations derived from the recorded GripLimit against body.obj: left (-.507,-11.568,2.770) mm, right (-.752,11.574,3.609) mm. The 22.013/22.293 mm figure is the raw cylinder/handle discrepancy, not the translation magnitude (11.906/12.147 mm). Other controllers receive zero Index correction; they use available SDK/component hand frames, otherwise the raw hand fallback. No per-curl fit or 25 mm discontinuity remains.

## Placement review (2026-11-12)

SkeletalMatrices reuses 31 target Vector objects/tables per hand and computes a single numeric rigid transform per draw. Per-bone pose angles, which the retargeter never consumed, are no longer allocated. draw_target_pool checks object identity and absence of angle payloads. Wrist and palm-motion checks are stability checks of the fixed attachment, not independent placement evidence.

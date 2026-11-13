# vr_tools_capture.py

Read-only helper for vr_tools_check. Matches tools-roll/tools-pull captures to an observed
beam draw at their exact native pose id. The draw-start argument is NOT used for acceptance
and no draw-to-the-same-attachment world/pixel difference is reported as a measurement.

Projects the expected model attachment and target endpoint using recorded camera/eye data
and the frozen runtime centre projection (patches 0042/0056/0078, 0.4 m bound). Captured
opaque signed axial depth determines where the gun stops hiding that expected line.
Captured luminous beam pixels beyond this point supply per-row brightness centroids;
a robust straight-line fit measures lateral error at the projected attachment. Its closest
point is image_line_origin_pixel, an image-derived lateral alignment witness, not a claim
to recover an occluded three-dimensional or longitudinal root. Actual first visible beam
pixels are separately measured against the model's depth-derived visible boundary.

accepted(row) requires at most 2 INTERNAL render pixels of fitted muzzle alignment error
and 12 output pixels of visible-boundary error. Internal dimensions come from the captured
depth PNG; source pixels differ from upscaled colour pixels (1556x1376 vs 3112x2752 in the
frozen package). Both output/source-pixel errors, fit sample count, observed visible start,
expected attachment and measured occlusion length are reported. A test shifts actual
beam pixels while leaving reported draw/attachment identical and requires rejection.

Requires Pillow only for actual images. Missing/mismatched data yields no accepted sample;
truncated depth raises. No game/SDK/network/write activity or standalone exit code. Future
projection-contract changes must update this calculation. Command-clock correlation happens
elsewhere, leaving original records untouched.

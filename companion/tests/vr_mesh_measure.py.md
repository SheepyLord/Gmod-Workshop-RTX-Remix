# Independent geometric reductions

Fits a forward barrel-cap normal from measured vertices, using maximum-area
transverse vectors and a residual check. No product axis/grip table is read.
Placement checks keep the 20 mm independently fitted mesh/grasp bound and restore
the 12 cm shaft-weapon wrist envelope. Other rig-marker distances remain reported;
their independent mesh/grasp test is still translation-sensitive. Unit mutations
shift product grip/placement 3 cm and skew the actual mesh barrel 2.9 degrees.
No SDK, renderer, files or process side effects; invalid geometry raises ValueError.


plane_fit reports the cap normal, residual/spread-based uncertainty with a conservative1e-4unit export allowance; plane_axis remains its direction-only accessor.

The placement-sensitive fine grip bound is5mm. Bone landmark distances are separate observations, not a zero-by-construction precision certificate.

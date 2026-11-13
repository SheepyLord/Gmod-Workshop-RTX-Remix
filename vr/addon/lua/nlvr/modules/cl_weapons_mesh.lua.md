# Posed stock weapon geometry

Measurement-only helper for crowbar, stunstick and SMG world models. At authored
pose/scale one, reads their skinned mesh with a 65536-vertex bound. Semantic shaft
or barrel-ring regions yield an axis from two bounding centres. Melee grips project
the holding hand's reference grasp onto the actual shaft, so handed/hand-size frames
participate. A real mesh end supplies the strike point; no old fixed tip length is used.

No hooks, cvars, files or SDK calls. Called only by Model.Measure, never the draw path.
Missing mesh data returns nil so the caller can use declared model bounds rather
than inventing an old calibrated length. Independent diagnostics use separate
rendered-mesh/hand-bone fits and mutation tests.

Stunstick handle cross-sections now cover the full measured rings. The independent fixture derives sections from raw geometry gaps and narrow radial support; it does not import this table.

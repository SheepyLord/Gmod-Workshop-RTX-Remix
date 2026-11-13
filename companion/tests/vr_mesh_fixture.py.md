# vr_mesh_fixture.py

Generates `fixtures/vr_mesh_witnesses.json` from declared raw model/bone exports and
recorded rendered-hand observations. It reads JSON inputs only: no weapon module,
product grip table, reported `palm_frame`, or `frame.grip` is read. Non-shaft models use
their authored `ValveBiped.Bip01_R_Hand`; there is no grip box or sampled grip midpoint.
Hand binding is reconstructed from the physical hand pose and actual rendered hand bone.
Two shaft models retain annotated straight cross sections, without choosing a grip station.
SMG barrel regions retain raw front-cap vertices independently of the product fit.

To reproduce the checked fixture on Q's machine, run from the worktree:

```powershell
python companion/tests/vr_mesh_fixture.py --models ../v4c/out/vr/v4c/review3/mesh-pose-read/model-bones.json --models out/vr/v4q/mesh-export-01/models.json --hands ../v4c/out/vr/v4c/review3/index-final-01/frames.json --output companion/tests/fixtures/vr_mesh_witnesses.json
```

The fixture records each input's relative path and SHA-256. The local regeneration test
compares the entire output; synthetic contracts still run when raw evidence is absent.
For fresh stock-model exports after the separately reviewed fixes repair, the existing
`vr_v4_geometry.py --export-meshes --simulate --both-locks --package <FIXED.gma>
--evidence out/vr/new-raw-models` now exports all16 models. It uses never-drawn measurement
models. Record matching hand observations with `vr_frames_poc.py` and its documented
pistol-left/right phases; feed that `frames.json` and the new `models.json` to this tool.
No native run is performed by the generator itself. Do not run full combined acceptance
until Claude confirms the repair.

SMG's 20-vertex cap plane has residual about3.38e-6 authored units. A conservative1e-4
unit position allowance and the measured .295-unit transverse spread give a deterministic
angular uncertainty bound .0402degrees; this is not a statistical confidence interval.
The .1degree agreement bound admits the supported fit and rejects the old1.875degree X
fallback. Inputs must be JSON exports; absent holding bones/uncertain fits fail closed.
Only the requested JSON output and its parent directory are written. Exit0 success;
bad/missing inputs or unsupported measurements exit nonzero. No game, Steam, network,
settings or package mutation occurs.

Round5 removes CAPS. Shaft sections are measured from significant empty intervals along the longest asset extent, choosing the last handle interval and narrow radial support; cross-section bounds include whole rings. SMG uses the forward-cap plane fit, never product ring boxes. HANDLE_CUTS are semantic raw-mesh annotations chosen on complete XZ/YZ geometry: the below-trigger pistol grips; SMG rear grip excluding its forward magazine; AR2/shotgun/Annabelle rear grips; crossbow lower grip; RPG complete irregular handle/guard assembly; camera side grip; medkit near face; grenade body excluding spoon; entire bugbait. Bounds are coarse semantic cuts, not boxes centred on a product point. GUN_AXIS records which end contains each visible barrel in those raw exports, including Annabelle-X. All raw vertices remain available. Source raw plots are out/vr/v4q/round5/raw-mesh-xz.png; regeneration uses the same declared raw JSON exports documented above and never opens sh_weapons.lua, cl_weapons_model.lua or cl_weapons_mesh.lua.

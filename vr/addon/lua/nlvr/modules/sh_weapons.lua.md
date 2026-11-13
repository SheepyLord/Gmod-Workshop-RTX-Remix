# Shared VR weapon definitions

Included by the session's client and server weapon modules. `Kind(class)` returns the
binding V4 kind (unknown classes are `swep`); `GunAngle` applies the pitch setting in the
controller's local frame. Contains world-model fallback lengths/foregrip/tip data in metres,
rigid wrist inversion, stable two-hand line, convergence and safe-muzzle trace helpers,
finite validation and the lazy model-less/no-attack hands weapon definition. Registration
occurs only when Hands() is called at Start. Hands has no attacks, ammunition or models,
is not spawnable and cannot automatically switch to/from itself. No disk inputs, hooks,
resources or exit codes.

ModelData keeps known world-model geometry (including foregrip) usable by unknown Lua classes without changing Kind or controls.

## Placement review (2026-11-12)

GripData contains six model-space grip-region midpoints selected from posed world-model mesh geometry. Those numeric facts are separate from barrel/class profiles and VR hand targets. Independent bone-local validation data and the measured regions are in companion/tests/fixtures/vr_weapon_grips.json. Unknown models may supply a named grip or model finger bones; fallback mount-only models have no validated physical grip locus.

Q4: the known physgun profile selects authored attachment 1 when no named muzzle exists, so its exported aim muzzle matches the emitter used by T. Arbitrary SWEP attachments are not guessed.

Ten more model-owned grip-region landmarks come from independently exported posed mesh geometry (Q4 fixture), including the bugbait body and the physgun handle. Placement no longer uses those models' wrist marker as a grasp centre. Numeric registration to a selected region is not physical skin-contact ground truth.

Independent review keys the physgun emitter attachment fallback by models/weapons/w_physics.mdl, not by weapon class. Reskinned physguns do not select an unrelated first attachment.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Obsolete crowbar/stunstick grip-point entries are removed; shaft grips and endpoints derive from posed mesh geometry.


The inferred modelGrips table and GripData helper were removed. Authored hand bones now locate stock holds; model-specific muzzle fallback remains.

Restored measured model-local handle points; they are placement data, independently checked by full raw mesh/holding-bone/finger witnesses. Annabelle uses authored-X barrel direction.

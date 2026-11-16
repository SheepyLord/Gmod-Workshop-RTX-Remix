# 0228: Back-face copies of imported characters deform with the layer facing outside

- Status: Accepted 2026-11-16 (the user's report; the checks in the report)
- Decided by: the agent, on the user's report of 2026-11-16: "the ragdoll from the imported models ... has a black
  region on her back skirt, hypothesis is due to clipping, investigate the cause and decide whether a general fix can be
  applied to the imported characters". The cause, the rule and where it runs were the agent's choice.
- Builds on: [0041](0041-hotloader-remix-depth-materials.md) (the Model Hotloader on fixed-function Remix),
  [0104](0104-painted-shadows-and-solid-hair.md) (what raster hides of an imported character and a path tracer
  shows), [0107](0107-the-model-hotloaders-natives-built-from-a-source-copy.md) (the Hotloader's natives built from
  the source copy kept here, with this repository's changes as patches).
- Report: [backface-twins-report.md](../handover/backface-twins-report.md); facts in RESEARCH.md, "Back-face copies of
  imported characters".

## Context

MMD clothing is often two layers on the same triangles: the outer cloth and a **back-face copy** (named `X+`, `裏`,
`内側` or a lining) whose triangles have the opposite winding, so single-sided rendering shows the outer layer from
outside and the copy from inside (under a skirt, inside a sleeve). Raster culling always hides the layer that faces
away, so the copy is never seen from outside, whatever it does.

The user's Fu Xua ragdoll (field session, modern_house) showed a sharp black patch on the skirt's hem. Measured in the
running game: the hem `裙下擺` and its copy `裙下擺+` coincide at rest, but **one vertex of the copy is skinned to the
skirt's physics chain** (`裙_5_8`/`裙_5_9`, dynamic rigid bodies) while its twin on the hem is skinned to the lower body
and the left leg. When the chain swings away from the leg, that vertex lifts the copy's five triangles up to 1.5 units
**outside** the hem. Primary rays cull the copy's back faces, so the camera never sees it; but its front faces now look
at the hem, so the hem's shadow and bounce rays all stop on it, in the dark gap between the layers: the hem goes black
there. Hiding the copy alone (in the native renderer) removed the patch; Remix's debug views showed the patch's albedo
and roughness as the hem's, its direct light 0. Clipping in the user's sense (the skirt pressed through the floor bends
the chain hardest) makes it larger, but any swing of the chain opens it, in dances too.

It is general: of the 206 imported characters in the user's library, 68 have such copies (262 pairs of parts), and 24
of them (20 distinct models) have copy vertices skinned or morphed differently from their twins: 752 vertices with other
skinning, 4,973 morph offsets (Furina, The Herta, Topaz, Robin, Silver Wolf, Firefly, Jingliu and others), mostly
skirts, sleeves and tops. In raster these mistakes never show; under path tracing each one can shade its outer layer
black when a pose or a morph opens it.

## Decision

1. **At load, each vertex of a back-face copy takes the skinning of its twin on the layer facing outside**: deform
   type, bones, weights and SDEF parameters (`native/backface_twins.hpp`, `weldBackfaceTwins`, called by `parse` in
   `model.cpp`). Twins are triangles of two different parts on the same three points (the light overlaps' 1e-4 rule) in
   the opposite cyclic order; a copy vertex follows its twin at the same point, and a copy of a copy the end of its
   chain. The outer layer is never changed, so the outside look is the model's own; the copy now deforms exactly like
   it, so it can no longer stand outside it.
2. **Its vertex morphs follow too**: per morph, the offsets that bring each copy vertex to its twin's are added with
   the morph (`buildTwinMorphFixes`, `Model::twinMorphFixes`, applied in `Instance::publish` with the morph's own
   offsets, and counted in the hardware-skinning bounds). A morph that moves only the outer layer now moves its copy; one
   that moved only the copy (Rin's `妊娠↓` on `裙+`) no longer does.
3. **Which layer faces outside is voted on the rest mesh**: up to 64 twin triangles per pair of parts cast a ray along
   each layer's normals through a coarse occupancy grid of the whole mesh (1/64 of its largest extent); the layer whose
   rays cross fewer surfaces faces outside. A side needs three votes and three times the other's. A pair the vote leaves
   open (both sides open, a ribbon) is decided by its names: a part named as a copy (a `+` suffix, `裏`, `内侧`, `內側`,
   `内側`, a trailing `内`, `inner`, `lining`) follows the other; a pair with nothing to go on is left as it was.
4. **Everywhere, not only under Remix**: the copies are back faces, so raster shows the same, except that from inside
   (under the skirt) the copy now matches the outer layer, as the model intends. Same-wound coincident layers stay with
   the Hotloader's light overlaps (their layer ranks, and their tiny separation under Remix); copies inside one part are
   not touched.
5. Recorded like the earlier changes to the source copy: `source/backface-twins.patch` and its section in
   `source/Source.md`, the four natives and the policy rebuilt with `tools/ci/build_hotloader.ps1`, `pins.json`'s note.

## Consequences

- No black patches from a copy layer standing outside its outer layer, on every imported character, in ragdolls,
  dances and morphs. The model files and their caches are unchanged; a character takes the change at its next load.
- Loading a character finds its twins once, on the loading thread: a hash of its points, a sort of its triangles and a
  64-cell grid (a median of 28 ms over the user's 206 characters, 100 ms for Fu Xua's 292,000 triangles, 455 ms for the
  largest, 941,000; the Hotloader's own light-overlap pass costs about three times as much). Nothing is added per
  frame but the copies' morph corrections, with the morphs that need them.
- A pair whose outer layer is itself mis-weighted keeps that: its copy now follows the mistake, which raster showed all
  along. A copy's own, different deformation from inside (a lining meant to move on its own) is given up.
- Clipping between different parts (a body poking through a skirt, a skirt through the floor) is not changed: that is
  the physics' collision and shows the same in raster.

## Alternatives considered

- **Cull back faces in Remix's shadow rays** (`rtx.enableCullingInSecondaryRays`). It would not help: where the copy
  stands outside the hem, its front faces look at the hem. And it changes light leaking for every map and model.
- **Push copy layers inward under Remix**, like the light overlaps' tiny separations. A few hundredths of a unit cannot
  hide a vertex lifted 1.5 units out by the wrong bones.
- **Snap the copy to its twin's drawn positions every frame.** The same result as matching their skinning, at a per-frame
  cost and only where the CPU skins.
- **The copy's average with its twin, without deciding which faces outside.** Half a mistake would reach the outside
  look (a 0.75-unit bump on Fu Xua's hem, half a morph on Rin's skirt).
- **Decide the outside by the bones** (normals facing away from the nearest body bone). Skirt bones lie in the cloth
  itself, so the direction to them says little; the mesh's own occupancy does not need the skeleton.

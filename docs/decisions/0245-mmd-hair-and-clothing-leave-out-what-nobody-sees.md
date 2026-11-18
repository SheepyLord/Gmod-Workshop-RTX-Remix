# 0245: MMD hair and clothing leave out what nobody sees

- Status: Accepted 2026-11-17 (the main thread's task of 2026-11-17: invisible entities of other add-ons
  interfere with the Model Hotloader's MMD physics)
- Package only: the Model Hotloader part (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua`)
  and one line of the VR add-on (`vr/addon/lua/nlvr/modules/sv_interact_physics.lua`); no loader, runtime or native
  change.

## Context

The report: some add-ons create invisible ragdolls or other invisible entities, and an imported character's hair, skirt
and other rigid bodies hit something nobody can see. The example given was Enhanced Death Animations (Workshop
3279383994). Read from its `.gma` (handover report and [RESEARCH](../RESEARCH.md) "Invisible helpers and the hair and
clothing physics"):

- **What it spawns.** Each death, crawl, writhe or revive animation plays on a helper, a `prop_dynamic` with
  `models/brutal_deaths/model_anim_modify.mdl`, spawned at the dying NPC and set to `COLLISION_GROUP_WORLD`
  (`animrag_death.lua` 934-940 and the same in `animrag_crawl.lua`, `animrag_writhe.lua`, `animrag_revive.lua`). The
  corpse's bones are pushed to the helper's animated bones. The writhe helper moves to the corpse's pelvis every tick
  and the crawl helper moves along with the crawl. Each helper is removed when its animation ends.
- **Why it is invisible.** The model's only bodygroup, `barney`, has two submodels: submodel 0 is blank (no mesh,
  no vertex) and submodel 1 is a Barney mesh (5 meshes, 3,609 vertices). The helper keeps body 0. It is not no-draw,
  its render mode is normal and its colour opaque: Source draws it, and there is nothing to draw. The add-on's own
  comment says that setting the bodygroup to 1 shows how it works.
- **Why hair and clothing hit it.** The helper has no physics object of its own. Its model's collision is jointed
  (15 solids, one per ValveBiped bone), and the game gives the helper a bone follower for each: a `phys_bone_follower`
  entity, no-draw by design and owned by the helper, that follows its animated bone. In the PoC a helper placed at
  an imported character's skirt added 15 objects to the scene and 97 to 100 skirt contacts. The Hotloader's scene
  capture (`bridge.cpp` `captureSecondaryScene`) reads every VPhysics object of the server's environment near a
  character, except triggers, fluids and objects whose collisions are off. It does not read collision groups,
  solidity or anything drawn. Moving objects count as objects in a character's secondary world (`secondary.cpp`,
  `sync`), and objects collide by default. Another add-on's hidden ragdoll is captured the same way: a stock ragdoll
  hidden in the same skirt made 42 to 52 contacts, as many as when it was drawn.

The capture already had an exclusion list, filled by the Lua side each tick ([ADR 0224](0224-the-animation-player-answers-a-click-with-its-built-flags.md)'s
`MMDHLSceneExcluded`); the natives drop every object of an excluded body's entity.

## Decision

1. **The server's scene capture leaves out entities nobody can see**, with all their physics bodies, at each tick
   while they are hidden. An entity is hidden when it is:
   - no-draw (`GetNoDraw`, the `EF_NODRAW` flag);
   - drawn with render mode none;
   - at colour alpha 0 under a render mode other than normal (with the normal mode Source draws the model opaque
     whatever its alpha);
   - an engine entity without a model (a scripted entity without one may draw its own meshes, as the broken glass
     shards of the fixes' glass add-on do);
   - a model scaled below 1 %;
   - a model whose selected bodygroups hold no mesh: every bodypart's selected submodel has no mesh or no vertex, or
     the model has no bodypart at all (animation-only models). The capture reads each model's MDL header once per
     session (`file.Open` on the `GAME` path: the bodypart count and offset at 232, each submodel's mesh count at 72
     and vertex count at 80 of its 148 bytes); a file it cannot read, or an MDL version outside 44-49, counts as drawn.
2. **What stays as it was:**
   - the world; brush entities are judged by the no-draw, render mode and alpha rules only;
   - a bone follower (`phys_bone_follower`: the hidden physics of an animated model, a strider's legs) is as visible
     as its owner;
   - a hidden entity with a drawn child counts as drawn: the sandbox bonemerge look, a base ragdoll made invisible
     with models merged onto its bones, shows those models where its bodies are;
   - a character this add-on draws (`mmdhl.IsMMD`) is hidden only by what its renderer follows: no-draw,
     `MMDHLNoDraw` or colour alpha 0. Its carrier model's own mesh and its render mode do not matter;
   - an entity with `MMDHLSceneStandIn` is not drawn itself but stands in for something drawn, and collides. The VR
     hands' physics spheres (`sv_interact_physics.lua`), hidden and never sent to clients, carry it, so hair and
     clothing still collide with the VR hands;
   - `MMDHLSceneExcluded` still excludes, whatever is drawn.
3. **Diagnostics:** `mmdhl.SceneHidden(ent)` answers for one entity, and `mmdhl.sceneDiagnostics.hiddenEntities`
   counts the hidden entities with physics that the last tick left out.

Considered and not done:

- **In the natives' capture.** The rendering state (EF_NODRAW, render mode, bodygroups) is not reachable from a
  VPhysics object without the engine's entity layout. The Lua side already classifies the nearby entities each tick,
  and the excluded list is the natives' interface for that. This also avoids rebuilding the four natives.
- **In each client's secondary world.** The server captures one scene, and every client shares it. The networked state
  the rule reads is the same for every client.
- **Leaving out what Source's own physics ignores** (collision groups such as debris or world, not-solid entities):
  that would turn off visible things in general, such as debris props, and the task ruled that out.

## Consequences

- Enhanced Death Animations' helpers no longer touch hair and clothing. The corpse, which is visible, still does. In
  the PoC ([report](../handover/invisible-colliders-report.md)): the helper in a skirt 97-100 contacts before, none
  after; an imported character's corpse animated by the add-on 179-266 before, none after; a hidden stock ragdoll
  42-52 before (two runs), none after. Drawn, the same ragdoll (45-51) and the helper with its mesh shown (98) collide as before.
- An entity drawn again (no-draw cleared, its render mode or colour back, a mesh bodygroup chosen) collides from the
  next tick on.
- Not covered:
  - hiding only on a client: a `RenderOverride` or `ENT:Draw` that draws nothing, a client-side `SetNoDraw`;
  - invisible material overrides (`SetMaterial` with a no-draw or fully transparent material);
  - per-bone hiding (bone scale 0 on a dismembered limb), because the natives exclude whole entities;
  - fading render effects;
  - client-side ragdolls, which are never in the server's scene.
- Cost: a few engine calls per entity near a character per tick, and one MDL header read per model and session.

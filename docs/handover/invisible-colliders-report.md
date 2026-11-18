# Hair and clothing leave out what nobody sees (report)

Claude, 2026-11-17, on the branch `invisible-colliders` (worktree `out\worktrees\invis`, from `main` at b197d905): the
Model Hotloader's `mmd_hotloader/lua/mmdhl/secondary_collision.lua` with its index entry, one line of the VR add-on and
an offline test. Package only: no loader (`winmm.dll`), runtime or native change. Decision:
[ADR 0245](../decisions/0245-mmd-hair-and-clothing-leave-out-what-nobody-sees.md).

## The task

From the main thread, 2026-11-17: some add-ons create invisible ragdolls or other invisible entities that interfere with
the Model Hotloader's MMD physics: an imported character's hair, skirt and other rigid bodies hit something nobody can
see. The example was Enhanced Death Animations (Workshop 3279383994). Find out what it spawns and why that is invisible,
find where the MMD physics picks up other entities, and leave out entities that are not drawn. Visible props, ragdolls,
NPCs, players and the world keep colliding, and an entity drawn again collides again. Test in the PoC. Scope: the MMD
physics only.

## What the add-on spawns and why nobody sees it

Read from its `.gma` in the field's Workshop content, unchanged (line numbers in [RESEARCH](../RESEARCH.md), "Invisible
helpers and the hair and clothing physics"):

- Each death animation plays on a helper, a `prop_dynamic` with `models/brutal_deaths/model_anim_modify.mdl`, made at
  the dying NPC (`animrag_death.lua` 934-940). The crawl, writhe and revive animations make their own helpers, and the
  corpse's bones are pushed after the helper's animated bones. Every death plays an animation by default.
- The helper is not hidden by any flag. Its model's only bodygroup, `barney`, has a blank first submodel (0 meshes,
  0 vertices) and a Barney mesh second; the helper keeps body 0, so it draws nothing.
- Its physics: in the PoC the helper had no physics object of its own but **15 `phys_bone_follower` entities**, one per
  solid of its jointed collision model, no-draw and owned by the helper, following its animation. The hair and clothing
  scene captured them as 15 moving objects. My first reading, one static object from the model's collision, was wrong.
  A first PoC run also showed nothing, because GMod does not mount a `.gma` copied into `garrysmod/addons`; the add-on
  had to be installed as an extracted folder.

The interference is in the MMD physics, not in the character's Source ragdoll: the contacts are the character's
secondary world's contacts with scene objects, and they went away when the helper's followers left the scene. Nothing
needed the user's go-ahead for a wider change.

## Where the MMD physics takes other entities

- The server's `Tick` hook in `secondary_collision.lua` (`MMDHL.SecondaryScene`) classifies the entities near each
  character and calls `native.CaptureSecondaryScene(owners, time, excluded, players, npcs)`.
- The natives (`source/mmdhl/native/bridge.cpp`, `captureSecondaryScene`) list every VPhysics object of the server's
  environment. They skip triggers, fluids and objects with collisions off, and drop every object of an excluded body's
  entity. They do not read collision groups, solidity or how an entity is drawn.
- Each character's secondary world (`secondary.cpp`, `sync`) mirrors the frame's objects in its box. Living players and
  NPCs count as players and NPCs, static objects as world, the rest as objects; objects collide by default.

## The fix

In the classification, an entity nobody can see goes to the excluded list with its bodies, every tick while it stays
hidden (`hidden` and `undrawn` in `secondary_collision.lua`):

- **Left out:** no-draw; render mode none; colour alpha 0 under a render mode other than normal; an engine entity
  without a model; a model scaled below 1 %; a model whose selected bodygroups hold no mesh. The last is read once per
  model from its MDL header; an unreadable file counts as drawn.
- **Kept:**
  - the world;
  - a bone follower whose owner is drawn (Enhanced Death Animations' followers go because their owner draws no mesh);
  - a hidden entity wearing drawn children: the sandbox bonemerge look, a base ragdoll made invisible with models
    merged onto its bones;
  - an imported character, unless its own renderer hides it (no-draw, `MMDHLNoDraw`, alpha 0);
  - a scripted entity without a model (broken glass shards draw their own meshes);
  - an entity with `MMDHLSceneStandIn`.
- **The VR hands:** their physics spheres are hidden server entities that stand in for the drawn hands.
  `vr/addon/lua/nlvr/modules/sv_interact_physics.lua` now sets `MMDHLSceneStandIn` on them, so hair and clothing still
  collide with the VR hands.
- **Diagnostics:** `mmdhl.SceneHidden(ent)`, and `mmdhl.sceneDiagnostics.hiddenEntities` (the hidden entities with
  physics the last tick left out).

Other entities of the package checked against the rule: the Hotloader's own props (`mmdhl_prop`, a cube model drawn by
its renderer), its legacy `mmdhl_ragdoll` (collisions off anyway), the glass panes (`nlglass_pane`, a plate model),
the seamless portals (alpha 255) and the remix light handle (no-draw: now left out, an invisible cube).

## Tests

**Offline:** [`test_hotloader_scene_visibility.py`](../../tools/tests/test_hotloader_scene_visibility.py.md), 9 tests
under LuaJIT on the shipped file, all pass. Against `main`'s `secondary_collision.lua` every scenario fails at its first
hidden entity.

**PoC** (gm_construct, RTX, 1600x900, Linlong as a frozen ragdoll with every collision box ticked, a scratch driver as
described in [TESTING](../TESTING.md)). Before: the published package `0.0.0-dev.20261117102000+a8e6cb04` (main). After:
this branch's `0.0.0-dev.20261118051859+42192dc3`. Contacts are the character's `objectContacts`, the most over 2.5 s
(mean in brackets); "mirrors" are the scene objects in its world; the world itself gave 2-3 mirrors and no contact.

| Step | Before | After |
|---|---|---|
| Stock ragdoll in her skirt, drawn | 47 (41), 18 mirrors | 45 (39), 17 mirrors |
| The same, no-draw | **46 (39)**, 18 mirrors | **0**, 2 mirrors; 1 hidden, 15 bodies excluded |
| Drawn again | 46 (42) | 49 (42) |
| Alpha 0, render mode transalpha (invisible on screen) | **44 (40)** | **0** |
| Render mode none | **42 (39)** | **0** |
| Alpha 0, render mode normal (drawn opaque on screen) | 43 (39) | 51 (44) |
| The add-on's helper at body 0 (blank), made as the add-on makes it | **97 (90)** | **0**; its 15 followers hidden and excluded |
| The same helper at body 1 (Barney drawn) | 98 (91) | 98 (88) |
| Back at body 0 | **100 (92)** | **0** |
| A citizen killed beside her: the add-on's helper and 15 followers, after 0.6 s | 10 (1), 32 mirrors | 0, 17 mirrors |
| Linlong killed as an NPC, her corpse animated by the add-on, after 3 s | **266 (134)**, 19 mirrors | **0**, 4 mirrors |
| The same after 6 s (the crawl helper, 15 followers) | **179 (165)**, 16 mirrors | **0**, 17 mirrors |

Screenshots: before, her skirt flares out around the no-draw or transparent ragdoll and the corpse's skirt stands off
her body; after, it hangs as with nothing there. Every run quit normally, with 0 Lua errors and the settings put back.
Its console has no `RTX guard` line for the new code.

**Gate:** `tools\test.ps1 -Config Release` with `NL_FIXES_CLONE` set, in `out\worktrees\invis`: see below.

## Not covered, not verified

- Not covered by the rule: hiding only on a client (`RenderOverride`, a client-side no-draw), invisible material
  overrides, per-bone hiding (bone scale 0 on a dismembered limb: the natives exclude whole entities) and fading render
  effects. Client-side ragdolls are never in the server's scene anyway.
- Not tested in the game: multiplayer and remote clients (they get the server's frame, so the rule applies there too),
  the VR hands (the offline test covers `MMDHLSceneStandIn`), a strider's or other animated NPC's bone followers
  (offline only), the bonemerge look (offline only), the field install (not touched).
- Cost: not measured. The rule makes a few engine calls per entity near a character per tick and reads each model's MDL
  header once per session.

## For the main thread

- Commits: see the branch; nothing is merged, pushed or published. The shared docs have additive edits only: the top of
  CHANGELOG's `[Unreleased]`, a ROADMAP paragraph before S1's, the ends of RESEARCH and TESTING, the decisions index
  after 0243, the handover index before S1's line, AGENTS.md's status line. ADR 0244 is left to the rejected loader
  branch.
- `packages/model-hotloader/files.json`: `inputs.py import` writes the source and repository of the entry it touches as
  absolute local paths; that entry now names `<repo>` instead (AGENTS.md rule 10). `inputs.py verify` passes.
- The PoC as left: `native-loader\config.json` names main's published package (`out\workshop\...a8e6cb04.gma`). The
  config found before the runs named `...ad9ad1a9.gma`, which no longer exists; that file is kept as
  `out\invis\poc\state\config.json.before` in the worktree. This branch's package is deployed until the next start
  redeploys. The add-on's test copy and the probe's data files are gone, and `out\r10\poc.lock` is released.
- The user's field game ran during the PoC sessions (started from Steam at 21:54 local); it was left alone.
- Evidence (worktree `out\invis\poc`): `before` (stock ragdoll; the add-on not mounted), `before2` (with the add-on
  mounted), `before3` (the add-on's kills), `after`. Each has the session records, the console log and the probe's
  `results.json`, `events.json` and screenshots. The scratch driver and probes are in `out\invis\poc\` too.

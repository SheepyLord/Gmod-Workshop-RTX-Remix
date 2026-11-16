# 0229: ToPBR takes the map's own surfaces unless the player widens it; marked experimental in the menu

- Status: Accepted 2026-11-16 (the user's request of 2026-11-16)
- Package only: the RTX fixes part (its native module with a fourteenth patch, three of its Lua files) and the
  companion's catalogs and guide; no loader or runtime change.

## Context

The user: "Adjust the topbr function, allow user to limit its application range, by default it should only work on
map mesh and nothing else. Also marks it as an experimental feature in the menu."

ToPBR (world conversion, crtx_topbr_enabledc, off by default) built PBR materials for every scene material the RTX
fixes' texture tracker saw drawn: the map, its props, spawned props, weapons and view models, NPCs and effects, all
but imported characters (which have Imported game PBR). Its queue is filled in native code: the material pipeline's
worker calls cQueueMaterialsForProcessingc whenever a new material is drawn, and that walks every material the tracker
holds (cmaterial_pipeline.cppc, cto_pbr.cppc). No Lua runs in that path, so Lua alone could not narrow it.

What "map mesh" is has a precise source: the map's BSP names every material its faces use (world brushes,
displacements, brush entities, overlays). Static props are models; everything else drawn is not the map.

## Decision

1. **A fourteenth native patch, [topbr-scope](../../packages/fixes/licenses/oversized-skinning/topbr-scope/README.md)**:
   every place that queues world conversion asks a range (cScope::Filterc). A restricted range takes only material
   names the game's Lua has given it; a material outside it is not marked done, so a wider range takes it later.
   Names are compared as the tracker records them, so the BSP's patched names (cubemap patches, a blended
   displacement's WVT patch material and its second stage) meet the drawn ones.
2. **The player's setting decides whether the range is restricted**: crtx_topbr_scopec, read natively from the
   engine's convar list on the game thread, as R19 reads crtx_topbr_enabledc ([ADR 0112](0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)).
   0, the default, is the map's own surfaces; 1 adds the map's props (its static props' models, and the physics,
   dynamic and door props there are); 2 is everything ToPBR can convert, as before. Lua only adds names (bounded:
   any server's client Lua reaches the bindings, and more names only mean what 2 already does).
3. **The client driver names the range**: at a map's start it sends the BSP's materials
   (cgame.GetWorld():GetMaterials()c and NikNaks' texture list, again ten seconds later), with props also the props'
   model materials (the c.mdlc header's names) and, every two seconds, those of new props. A narrower range clears
   the cache, so the next publication carries only what the new range converts.
4. **Marked experimental**: the page is "Map and prop PBR (ToPBR, experimental)", it opens with "Experimental
   feature.", its switch is "Enable ToPBR (experimental)", and "Apply to" chooses the range, with help naming what
   the map's own surfaces are. The guide's line says the same. Ten texts and the guide line in six languages.

Imported game PBR (crtx_topbr_game_mapsc) is a separate feature for imported characters and stays as it was.

## Consequences

- A player who turns ToPBR on gets PBR on walls, floors, ceilings, displacements and brush entities only; props,
  weapons, characters and effects keep their own materials until the player widens the range.
- Narrowing the range clears the cache, so the narrower set is converted again from the start.
- The fixes module grows by about 9 KB; the patched native tree is cca07cbbf...c (ctools/ci/pins.jsonc).

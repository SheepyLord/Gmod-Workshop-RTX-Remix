# Game assets without a map: weapons, items and hands

The map pipeline also remasters what the game itself ships: Half-Life 2's and GMod's weapons (view and world
models), the hands every view model shows, and the spawn menu's entities (ammunition, health kits, batteries,
chargers, mines). The first was Half-Life 2 PBR RTX (`source/hl2_pbr_rtx/tools`, branch `claude/hl2-pbr-rtx` of the
user's fork, 2026-11-26). Everything below is what differs from a map; the stages after the inventory are the map
pipeline's.

## Scope

The user asked for "all vanilla halflife 2 weapons (like crowbar, physics gun) and entities", then limited it: "Limit
the enhancement to the spawnable prop entities only (not NPCs) like magzine, health pack" (2026-11-26). Weapons,
their hands and the spawnable entities are in; the NPCs (their bodies, faces and the citizen models) are not, unless
asked. `inventory_models.py`'s `NPCS = False` keeps them out; the NPCs' own weapons' world models stay (they are
weapons).

## Inventory from the game's spawn lists

- There is no BSP to read. The game says what it spawns: `spawn_inventory.py` (server realm, the game running a map)
  creates every entry of `list.Get("Weapon")`, `list.Get("SpawnableEntities")` and `list.Get("NPC")` once and records
  its models: a weapon's world model and `GetWeaponViewModel()`, an entity's model, the NPCs' weapons, and
  `player_manager.TranslatePlayerHands` for every player model (six hands models: citizen, refugee, Combine, Chell,
  Counter-Strike, Day of Defeat). Vanilla means the "Half-Life 2" and "Other" categories; add-ons' entries (the
  Model Hotloader's gun, Seamless Portals, the glass panes, Remix lights) are left out by category and class.
- GMod's engine weapons draw `c_*` view models; many SWEPs use the Half-Life 2 `v_*` ones: take both (same textures
  mostly, plus the `v_` hands).
- `inventory_models.py` writes the map inventory's shape (`materials`, one pseudo-map `hl2` with `prop_instances` and
  `models`), so `tex_jobs.py`, `oai_tex.py`, `compose.py` and `build_mod.py` run unchanged.
- **VMTs choose textures in DirectX-level blocks** (`">=dx90_20b" { $basetexture ... }` and `"<dx90_20b" { ... }`):
  the Combine soldiers' sheets, the citizen turrets' skins. The offline parser does not evaluate them, and the RTX
  session runs the DirectX 7 shaders (`VertexLitGeneric_DX7`), which take the low-DX branch.
  `live_material_params.py` asks the game what each material draws (`IMaterial:GetTexture`), and
  `inventory_models.py` merges it. The RTX fixes' stand-ins (`rtx_solidcolor_*`) and the eyes' errors are skipped.

## Classes and maps

- A weapon sheet mixes steel, paint, polymer and rubber, so one class per texture cannot say metal. `compose.py`'s
  `metal_mask` puts metal where Source's specular mask passes `lo..hi` and the colour is grey (saturation under
  `sat[0]`, none above `sat[1]`), smooths it a little, and `metal_lift` raises the metal parts' albedo toward a metal's
  reflectance (Source darkened its steel for the cubemap's highlight). The mask is the `$envmapmask`, the base alpha
  (`$basealphaenvmapmask`, `$basemapalphaphongmask`) or the bump map's alpha (the phong mask, or
  `$normalmapalphaenvmapmask`); `tex_jobs.py` records `phong` and `phong_base_alpha` for it.
- Without any specular mask (the chargers, the HEV suit, most world models) `metal_mask`'s `nomask` lets the colour
  decide: mid and light greys metal, dark polymer and rubber not. With or without a mask, white and near-white is
  paint, not bare metal (`lum`, sRGB luminance 0.72-0.86): the health kit's white panels came out chrome before it.
- Classify by what the model draws, not by the texture's name: `chell_torso_diffuse` holds a whole torso, but only
  `c_arms_chell` draws it, and only its bare arms show: skin, not cloth.
- Recipes: `gun` (steel and polymer, metal by mask, emission from `$selfillum` masks), `gun_painted` (metal only where
  the paint is worn), `gun_metal`, `brass`, `machine` (the Combine's devices, chargers, mines, the HEV suit),
  `cardboard`, `skin`, `fabric`, `gear` (gloves and armour), `flesh`, `light`.
- **Rule order:** the hands live in `models/weapons/c_arms_*`; their rules must come before the weapons' general
  `^models/weapons/` rule, or the hands become weapon steel.
- Output sizes by how close a group is seen (`tex_jobs.py` `GROUP_SIZE`): view models and hands 4096, world models
  and items 2048, small parts at 8x their source. `ai_tex.py` runs its 4x DAT upscaler only when the target is at
  least twice the source: a 2880 px OpenAI answer goes to 4096 by Lanczos, not up 4x and back down.
- No parallax on model UV islands (their seams show).
- **Glows in the game's own colours** (`compose.py`'s `emit_source` on `gun` and `machine`): the whole `$selfillum`
  mask emits in the original texture's colours. Lighting only the re-rendered albedo's brightest texels under the
  mask (the lamps' rule) left the medkit's green vial dark with yellow flecks.
- **A glow tinted per player stays with the runtime.** The physics gun's view sheet (`v_superphyscannon_sheet`) takes
  the player's weapon colour through GMod's `PlayerWeaponColor` proxy; under Remix the RTX fixes'
  `cl_physgun_color_sync.lua` hands it to the runtime's legacy emissive path (`rtx.legacyEmissiveColorsString` per
  texture hash), which lights the albedo under its alpha. A replacement with an emission map of its own suppresses that
  path (`rtx_instance_manager.cpp`, `suppressLegacyEmissiveOutput`): the gun glowed white whatever the colour. Such a
  texture gets `legacy_glow` (`tools/overrides.json`): no emission map, the original glow mask in the albedo's alpha.
  Check it with another colour (`cl_weaponcolor "2.0 0.3 0.2"` glowed red). Don't give the albedo an alpha anywhere
  else: on a legacy-emissive draw a BC7 albedo's opaque alpha would light the whole surface.

## Hashes: LOD-clamped textures

A VTF 7.3 can carry an LOD control resource (tag `LOD`, the clamp's U and V as powers of two): the game loads at most
that size at the usual texture detail (`mat_picmip 0`), so Remix hashes the clamped mip, not the file's top one. The
AR2 ammunition crate's sheet is 512 px in the file and 256 drawn, the Magnusson device's 1024 and 512; the first build's
replacements for both never applied. `tex_jobs.py`'s `lod_skip` reads the resource and `remix_hashes` adds the clamped
mip's hash beside the top mip's (which a higher texture detail uploads). Maps are affected too: their props' VTFs can
carry the same resource. The live check (`live_hashes.py` after drawing every model, skin and player model's hands;
the RTX fixes' `RemixCategoryManager.ForceTrackTexture` draws a material off screen) is what found it.
- **Check every detail-baked source before it goes to OpenAI**: compare its mean with the plain source's. A
  weapon's `$detail` can be an effect layer (the super gravity gun's glow), and a hands sheet can carry another
  model's skin detail (the Chell torso): baked in as an ordinary detail they halved one sheet's brightness and left
  the other near black, and the image model kept the darkness faithfully. `tex_jobs.py`'s `JOB_OVERRIDES`
  `{"detail_bake": False}` sends the plain source.

## OpenAI's moderation and firearms

- The image edit endpoint refuses some firearm textures as "illicit" (`moderation_blocked`): the pistol's, the
  .357's and the AR2's view sheets, five world models, the tool gun's sheet and an ammunition box's art (10 of 80). The
  image decides: with the prompt's detail reworded to materials only ("machined dark steel, anodised aluminium,
  hard polymer and stippled rubber", no "gun" or "grip") the SMG's sheet went through and the pistol's was refused
  again. Do not try to get around it (tiles, crops): a refused texture keeps the local upscale and gets the same PBR
  maps. List them in `work/oai_blocked.json` so they are not sent again.
- The pilot and the run cost $8.41 for the 80 textures in scope (63 answers kept, 15 of them by eye: sleeves, gloves
  and hands whose parts moved 2-5 px on a 1024 px sheet, the Combine gloves dark and low in contrast), and $0.38 more
  for the two sheets sent again from their plain sources. The first run, sent before the user narrowed the scope, had
  already answered 131 NPC textures ($9.98, kept in `work/oai`, unused): send the core of a request first (here the
  weapons and items, which every reading of it includes) and its broader parts last.

## The mod's folder sorts first

Several map remasters and content packs replace a few of these assets as props of their maps (BigCity's pack the
physics gun's sheets and the Combine hands, Country Estate's the camera, gm_boreas an ammunition box, base_mod the
chargers' glass). The folder that sorts first owns a shared hash, so the asset pack's folder is `!hl2_pbr_rtx` (and
its packed copy `!hl2_pbr_rtx_pack`): it sorts before them, as `!advanced_material_editor` already does. The path
rules allow `!`. What another mod does deliberately stays its own: the chargers' glass is classed `skip`.

## Before and after: the showroom

`showroom.py` shoots every weapon from the player's eyes (view model, HUD hidden, five seconds after the draw), and
every world model and item as a `prop_dynamic` in front of a camera framed on its bounding box, one at a time, the
same framing in every session (the spot in `work/showroom_spot.json`). A stock session (the mod's folder not in the
game) and a remaster session then compare view for view (`showroom.py compare stock after` writes the docs' pairs).
Small items need the camera close (12 units at least); an NPC needs `DropToFloor` and its idle sequence
(`SelectWeightedSequence(ACT_IDLE)`), or with `ai_disabled 1` it floats in its reference pose.

## Workshop screenshots without a map

`beauty.py` shoots compositions from `tools/workshop_hl2.json`: first-person views (the weapon given and selected, the
HUD hidden) and still lifes of world models and items, spawned for the shot (`physics` ones dropped onto their sides and
frozen once they settle), each at its own sky hour. On gm_construct the plaza east of the spawn and its red wall work
as a set; the sun sets in the north-west: 19.0 is golden light with long shadows, 19.6-19.9 dusk, when the glows
carry the picture (the physics gun, the AR2, the medkit, the Combine tech). `workshop_shots.py export hl2 ...` makes the
1920x1080 copies; the PoC's FPS counter sat at the bottom right, which `clean_overlay` now paints out too.

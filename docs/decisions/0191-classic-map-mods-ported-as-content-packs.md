# 0191: Classic map mods ported as content packs

- Status: Accepted 2026-11-12
- Decided by: the user ("These maps were already made with complete PBR for remix, package them into .gma and make
  sure the visual looks correct. This is a porting task"), for the classic install's Poolday and SafeHouse mods;
  Claude choosing the names, the merge rule and the checks.
- Builds on: [0023](0023-content-packages-and-modern-house-item.md) (content packages, one per map; its "Poolday does
  not ship" was about the RTX package, which still does not carry it), [0027](0027-content-packages-from-any-subscription.md),
  [0111](0111-content-packages-only-from-subscribed-items.md).

## Context

- The user's maps finished for the old RTXLauncher install keep their look as loose folders in that install's
  `rtx-remix\mods` (backup `E:\RTX_c_backup\GarrysMod_RTX_c`): New Pool Day 2 (`gm_new_pool_day2`, Workshop
  3096281917) as `Poolday` plus two fix mods (`Poolday_mirror_fix`, `gmodrtx_poolday_fix`), Safehouse
  (`gm_csgosafehouse`, 944959992) as `SafeHouse`. No Lua. The field had copies of the three Poolday folders,
  placed by hand.
- The runtime ranks mod folders by name and takes each texture, mesh or light hash whole from the first folder
  that replaces it; inside one folder, sub-layers compose attribute by attribute; an empty mesh override registers
  nothing (read in the runtime source, 2026-11-12; [RESEARCH.md](../RESEARCH.md), "Classic map mods as content
  packs").
- Remix replaces a hash on every map. Safehouse shares 8 stock prop textures with three of the user's remasters
  (`gm_br_rtx`, `gm_brmovie_complete_rtx`, `modern_house_rtx`). Pool Day's water fix replaces the RTX fixes' old
  water stand-in texture, which RTX Water (in the RTX package) now leaves undrawn.

## Decision

1. **One content package per map, a Remix mod only**: `pool-day-rtx` (`Pool Day RTX`, mod `pool_day_rtx`) and
   `safehouse-rtx` (`Safehouse RTX`, mod `safehouse_rtx`), named after the map without a game (the map's title is
   `Safehouse (CSGO)`). Kinds `root-files` only, so any subscriber's loader may deploy them (ADR 0027, 0111).
2. **Several folders become one without changing a hash**: each classic folder is copied unchanged under its old
   name inside the mod, and a new `mod.usda` lists them as sub-layers in the runtime's order. The merge is allowed
   only when no later folder sets anything on a hash an earlier one owns
   ([port_classic_mods.py](../../skills/workshop-content-pack/scripts/port_classic_mods.py.md) refuses otherwise).
   For Poolday the two shared hashes pass: Poolday sets both values the mirror fix sets on `3C0A7FF562C52317`,
   and its `345F539D9A62C372` mesh prim is empty, so the mirror fix's category change was and stays live.
3. **The pack only adds.** The lower-case names sort after the user's remasters, so on a machine with both, each
   remaster keeps its shared textures and Safehouse shows theirs for those 8 props; the classic upper-case
   `SafeHouse` would have taken them from the remasters on their own maps. A pack never takes a hash over from
   another remaster by its name.
4. **What the mod never had is not referenced.** Poolday names 39 maps it does not ship (20 metallic, 7 height,
   6 normal, 6 roughness); they become `@@` (no texture, which is what Remix drew), removing 39 `err:` lines from
   the Remix log. Files no layer reaches stay out.
5. **Checked in the field**, with the hand-placed copies moved out of `rtx-remix\mods` for the check and put back
   after, the archives as local packages, each view with the pack and with Remix's replacements off, and the
   map's live texture hashes against the pack's.
6. **Not uploaded.** Item, visibility and description are the user's call; the descriptions name the global
   replacements.

## Consequences

- Players of the two maps get each look from one hidden or public item once the user uploads it; the user's field
  keeps its hand-placed Poolday until they remove it (the hand-placed `Poolday`, upper case, wins over the pack).
- A pack with no Lua cannot keep a replacement to its map: shared textures change on other maps too. A future
  remaster of these maps would scope them with tag textures (remix-map-pbr skill).
- The workshop-content-pack skill gained the procedure, `port_classic_mods.py`, and `usd_refs.py`, which also lets
  `check_pack.py` read nested and binary `.usd` layers.

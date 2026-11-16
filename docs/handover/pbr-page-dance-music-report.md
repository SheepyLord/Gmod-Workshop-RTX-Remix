# Imported game PBR and a dance's music: report (2026-11-16)

The user's report of 2026-11-16, with a screenshot of Imported game PBR (RTX Remix tab, Rendering): the character list
set to the character the Model Hotloader comes with, an empty material list, and one material's status reading
"none":

> 1. The imported PBR menu does not work and the information is not useful. Nothing is being loaded for models with
>    PBR, the model's PBR status (what PBR is applied and what is the name) is not shown.
> 2. The animation player, if when dance is being player and the NPC become unavailable (died, removed), the music
>    stops. But when the user spawn the same NPC again in a later time, the music resumes playing.

Branch `pbr-panel-dance-music`, by Claude. Package only: the fixes part's Lua (`packages/fixes`, GPL-2.0) and the
character motion importer part's Lua (`packages/character-motion-importer`); no loader, runtime or native change.

## 1. Imported game PBR

### What was wrong

Measured first in the PoC with the published package (gm_construct, RTX on, 1920x1080; `out/msep/poc/pbr_probe.lua`,
evidence in `out/qa-poc/game-pbr-panel/01-before`):

- **The page said only what the game maps were doing.** The character the Model Hotloader comes with draws its PBR
  from the Remix mod `mmdhl_pbr_linlong` (ADR 0231). With her in view, 14 of her 30 materials had a live texture hash
  (`RemixMaterial.GetTextureHash`) and 12 of those were that mod's, yet every row read "none" or "waiting" (the game
  maps' state) and the status showed a texture path.
- **The list went blank.** The spawn menu builds a tool page once, when it is first shown, and keeps it, so the page's
  character list kept the entities of that moment. Choosing one that had since been respawned or removed, or pressing
  "List looked-at character" while looking at no character (usual with the spawn menu open), rebuilt the list from
  nothing while the status kept the earlier material: the user's screenshot.
- **Each row's picture was empty:** a model material draws nothing in a 2D image.

### What changed

`packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua`, its R12 section:

- **Each row** names the material, then the PBR Remix draws for it: the mod in `rtx-remix/mods` that supplies its live
  texture hash, from the Advanced Material Editor's index of the mods in the runtime's order
  (`AdvMat.RTX.Enhance.Lookup`), with the maps that mod gives it; an Advanced Material Editor profile; game maps by
  family; "No PBR"; or "Not drawn yet". Then the hash. Short lines: the game's word wrap dropped the first letter of a
  wrapped row line.
- **A picture** for a drawn material: an `UnlitGeneric` of its base texture, made once. Nothing unseen is loaded for a
  picture.
- **A count per source** under the character ("11 × Remix mod: mmdhl_pbr_linlong", "17 × Not drawn yet", "2 × No PBR").
- **The selected material's status:** what is in effect, its hash, the game maps' state and family, a refusal's reason.
- **The characters:** refreshed while the page stays built. A removed character empties the page with "No character:
  spawn one, or look at one and list it." and resets the status; a new one fills it; "List looked-at character" keeps
  the shown character when the eyes are on none.
- Seventeen new texts in the page's own six translations (the material editor's own name for itself where the page
  names it).

### Checks

- `tools/tests/game_pbr_panel_harness.lua` (`test_topbr`): the earlier checks, and with fake live hashes and a fake
  index of the mods: each source line, the rows' lines with the hash, the counts, pictures only for drawn materials and
  only once, and the characters followed (removed: empty page, status reset; respawned: filled again).
- In the PoC with the branch's package (`out/msep/poc/pbr_probe2.lua`; runs `02-branch` and `03-branch`): with the
  character in view the page listed her 30 materials: 11 "Remix mod: mmdhl_pbr_linlong" (normal, roughness and, for
  the face and eyes, emission), the eye white and the skin "No PBR", 17 "Not drawn yet"; 13 pictures; the count line
  as above; the status "In effect: Remix mod: mmdhl_pbr_linlong (normal, roughness, emission)", her face's hash, game
  maps none. After `gmod_cleanup`, with the page still built: no rows, "No character: ...", the status reset. Spawned
  again (at the same entity index, 88): the page filled again with the same lines. The screenshots show the rows'
  lines whole beside their pictures.

## 2. A dance's music ends with its dancer

### Cause

- **Server** (`mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua`, `update_playback_state`): a dancer that is no longer
  usable (killed or removed) has its playback state torn down every tick, but `mmdvmd_audio_stop` was not sent. The
  "stop all" path's teardown sends it, and `MMDVMDNPC.StopPlayback` returns at once for an unusable entity.
- **Client** (`cl_menu.lua`): the music follows its dancer by entity index, because a start can reach a client before
  the dancer is networked to it. With the dancer gone the volume gate closed (silence) but the song kept playing.
  Source reuses entity indices, so the next entity at that index (the user's newly spawned NPC) opened the gate in the
  middle of the song.

### What changed

- Server: both teardowns (an unusable dancer, a dance without frames) send the stop.
- Client: the music belongs to the entity its index first resolves to. When that entity is gone the song stops, also
  without the server's stop (an older server, a lost message), and a later entity at the same index is never adopted.

### Checks

- `motion_server_harness.lua` scenario `dancer_gone_music` (`test_motion_server`): a dance with its music playing, its
  dancer invalidated, one Think: the state goes and the stop is sent. It fails on the code before the fix.
- `motion_tab_harness.lua` scenario `dance_music` (`test_motion_tab`): the client's music stops when its dancer becomes
  invalid with no stop from the server, a new NPC at the same index brings nothing back, and a start that arrives
  before its dancer exists waits for it and then follows it. It fails on the code before the fix.
- Not checked in the game: a dance with music in a PoC run.

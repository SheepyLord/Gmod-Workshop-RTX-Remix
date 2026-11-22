# 0249: Which sky a map shows: the RTX sky by default, the map's own sky per map, a map's RTX version's sky above

- Status: Accepted 2026-11-20 (the user's request and their three answers below); supersedes in part
  [ADR 0031](0031-physical-sky-time-and-weather.md) (rule 1's "the map's skybox": now one choice per map, with its 3D
  skybox, and the default for other maps); extends [ADR 0248](0248-a-maps-add-on-keeps-a-fixed-sky.md) to every sky
  that is not the RTX sky; superseded in part by [0253](0253-the-skys-chat-line-is-off-by-default.md) (decision 6: the chat line is
  off by default)
- Package only: the companion ([nativeloader_sky.lua](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md),
  [map_sky.lua](../../companion/nativeloader/lua/nativeloader/map_sky.lua.md)) and its translations. No `winmm.dll`,
  runtime or fixes change.

## Context

The user's request of 2026-11-20, word for word: "Improve the compatibility of the RTX addon to the game's own skybox.
We should replace other map's skybox to our own RTX skybox by default, but we also allow user to switch back to the map
(3D) skybox if applicable. Display a chat message about this when map join. Make sure the confusion on gm_stelliferous
RTX can be resolved and avoided in the future and allow more modding and enhancement (like custom skybox for different
map that comes above the stock RTX sky we have)".

- **The confusion on gm_stelliferous RTX.** Its remaster shows the map's own orbit skybox; the companion's physical sky
  replaced it whenever "Follow the map's sun" was unticked (ADR 0105), so the station hung under a pale blue daytime
  sky. Which sky showed depended on a setting that does not mention the map's sky, and nothing told the player which
  sky they saw or how to get the other. ADR 0248 (the user's "Yes, keep orbit sky") fixed that one map with a Lua hook.
  No GitHub issue or Workshop comment names the map; two Workshop comments asked where to stop the day cycle.
- **What RTX starts did with a map's sky** ([RESEARCH.md](../RESEARCH.md), "ADR 0249"):
  - the physical sky (`rtx.skyMode 1`, the default) drops every draw of the sky camera, so a map's sky textures and its
    3D skybox pass never show; `nativeloader_sky 0` ("The map's skybox") gave back the 2D sky textures only, for every
    map at once;
  - the session sets `r_3dsky 0` (the fixes' `autoexec.cfg` and their per-map `default.txt`, 1 s after a map starts),
    and the companion's guard keeps it there against other Lua;
  - with `r_3dsky 1` and `rtx.skyMode 0` the runtime moves the sky pass's geometry out to the main camera
    (`rtx.skyReprojectToMainCameraSpace`, `rtx.skyReprojectScale 17` in the package's layer): gm_construct's city and
    gm_flatgrass's endless grass and hills come back, path traced at true scale. But the session draws the whole map in
    every view (`r_novis 1`), so the sky pass drew the playable map too, magnified 16 times around the camera (a dark
    shape over gm_flatgrass);
  - with visibility by the PAS (`r_novis 0`, `rtx_patch_forcenovis 0`, `rtx_patch_vis_pas 1`: the RTX fixes' patch,
    which the gm_stelliferous and Backrooms remasters use for their maps) the sky pass draws the skybox room alone, and
    the skybox room's miniature, which the whole-map drawing shows overhead on gm_construct, goes too;
  - `rtx.skyReprojectScale` cannot be set from Lua (RemixConfig's allowlist), so a 3D skybox at another scale than 16
    (gm_stelliferous 64, gm_construct_renovation 32) would land at the wrong distance;
  - a client's `sv_skyname` in a single-player game changes the 2D sky at once.

## Decision

1. **The RTX sky by default, on every map.** As before.
2. **This map's sky, remembered per map** (the user's answer "Per map"): `nativeloader_sky_here` (`auto`, `rtx`, `map`,
   `addon` or a sky file's id) and the "This map" choice in RTX Remix > Sky and weather, saved in
   `data/nativeloader_companion/sky_maps.txt` and applied from the map's start. `map` is **the map's own sky**: its sky
   textures (`rtx.skyMode 0`, the map's own sun back) and, where it has one at scale 16, its 3D skybox (`r_3dsky 1`
   with visibility by the PAS while it shows; what it changed is recorded in `nativeloader_sky_engine_saved` and put
   back when it goes, also at the next map's start; the fixes' question before `r_3dsky 1` is held back for this
   change). A map with no sky faces, or whose sky textures are missing, has no sky of its own: the RTX sky stays, and
   the chat line and the panel say so. A 3D skybox at another scale is left out, and said.
3. **Other maps** (`nativeloader_sky`, its values unchanged): the sky of maps without a choice of their own, the RTX sky
   (1) or their own (0).
4. **A map's RTX version's sky comes above the RTX sky** (the user's answer "The pack's own sky"):
   - an add-on that sets the sky from Lua, by the hooks of ADR 0031 and ADR 0248, unchanged;
   - **a sky file**, content any add-on or content package may ship: `data_static/nativeloader/sky/<map>/<id>.json`,
     version 1, `sky` `map` (the map's own sky, which the package's Remix mod may have replaced) or `skybox` (another
     sky by name, `skyname`, in `materials/skybox`; set through `sv_skyname`, so in a single-player game only),
     `title`, `skybox3d`, `default` and `priority`. No code: the companion checks it (at most 8 files of 16 KiB a map,
     the id, every field, the sky name's faces present) and leaves out what does not pass, naming it in the console.
     The guide for modders is [docs/MAP_SKY.md](../MAP_SKY.md).
   `auto` shows the add-on's sky, else the first sky file that is not only offered, else the choice for other maps.
5. **A setting changed in the session** (the user's answer "Yes, keep ADR 0248"): on a map that shows any sky but the
   RTX sky (an add-on's, a sky file's, the map's own), a change of time, weather or another sky setting shows the RTX
   sky until the next map's start, as ADR 0248 decided for a fixed add-on sky. Choosing a sky for the map again shows
   it again; going back to an add-on's sky during the session waits for the next map's start, when the add-on sets
   it. The weather is the RTX sky's: under the map's own sky what it set goes back to Remix's own values.
6. **One chat line at the map's start** ("[RTX] ..."), 6 s after `InitPostEntity`, once per map load, in the player's
   language (the companion's six): which sky shows and why, and how to switch (the console command and the menu's
   path), or that the map has no sky of its own. "Say which sky shows" turns it off (`nativeloader_sky_message`); the
   console always gets it in English.
7. **For add-ons**: `NATIVELOADER_SKY.mapSky()` (what shows and why), `NATIVELOADER_SKY.line()` (the line's words), and
   `takenOver()` also true once the player chose another sky for the map. `takenOver()` runs no owner hook, since an
   add-on asks it from its own answer to that hook. An add-on that names itself only while its sky shows (gm_stelliferous
   RTX) is remembered for the rest of the map's session, so the line can say its sky returns at the next map's start;
   one that never named itself (the RTX sky chosen from the start) but answers `NativeLoaderSkyFixed` is offered as
   "its RTX version has a sky of its own".

## Consequences

- gm_stelliferous RTX keeps its orbit sky by default, and the chat line names it and says how to get the RTX sky; the
  same holds for any map whose RTX version declares its sky. No setting that does not name the map's sky decides it.
- gm_construct's city, gm_flatgrass's grass and hills and every 3D skybox at scale 16 can be had under RTX, one map at a
  time. While a 3D skybox shows, the map is drawn by the PAS, as the original game draws it around the camera: parts
  of the map out of the PAS are not in reflections or bounce light.
- A player who had `nativeloader_sky 0` keeps the maps' own skies on every map, now with their 3D skyboxes; the
  weather no longer adds fog or rain to them.
- The RTX sky still shows the skybox room's miniature where the whole-map drawing puts it in view (gm_construct,
  overhead); that needs the PAS, or a way to leave that room out, which the default does not change.
- The in-game guide's Sky and weather picture and its legend describe the new controls.

## Alternatives considered

- **One switch for all maps** (today's `nativeloader_sky`): the user chose per map; the switch stays as the default
  for other maps.
- **The RTX sky above a map's RTX version's sky**: the user chose the pack's sky first.
- **Only the explicit switch replaces a fixed sky** (a weather change would leave space as it is): the user kept ADR
  0248's take-over by a setting.
- **The engine's 3D skybox pass under the whole-map drawing**: it doubles the map, magnified, around the camera.
- **The fixes' own 3D sky renderer** (`rtx_3dsky`): it works only in their Performance Mode, which replaces the
  world's drawing and breaks mesh replacements.
- **Setting `rtx.skyReprojectScale` per map**: RemixConfig refuses it (the review's allowlist, a native change in the
  fixes); a later change can allow it and show 3D skyboxes at other scales.
- **Sky files as Lua** (an add-on's code naming its sky): a hook already serves add-ons with code; a declaration that
  any content package can carry, read at the map's start without timing rules, is safer and simpler.
- **A sky file that sets Remix options**: a declaration chooses among skies the companion already knows how to show;
  options stay with the add-ons' own Lua and Remix's files.

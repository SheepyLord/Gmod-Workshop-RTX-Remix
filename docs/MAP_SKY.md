# Giving a map's RTX version its own sky

In RTX starts every map shows the RTX sky by default: the runtime's physical sky with a sun, clouds, stars, a moon and
weather, driven by the companion's Sky and weather settings. A map's RTX version (a content package, a remaster's
add-on) can bring a sky of its own, which shows **above** the RTX sky: by default on that map, with the player free to
pick the RTX sky or the map's original sky for that map ([ADR 0249](decisions/0249-which-sky-a-map-shows.md)). At the
map's start one chat line tells the player which sky shows and how to switch.

There are two ways. A **sky file** needs no code and is the one to use for a sky that is a picture: the map's own
skybox (perhaps replaced by your Remix mod) or another skybox. A **Lua add-on** that sets the sky itself (a time of day
of its own, an API sun) answers the companion's hooks.

## A sky file

A JSON file in your add-on (Workshop item, content package or a folder in `garrysmod/addons`):

```
data_static/nativeloader/sky/<map>/<id>.json
```

- `<map>` is the map's name as `game.GetMap()` gives it (`gm_construct`); `<id>` is yours: lower-case letters, digits,
  `_` and `-`, at most 48, not `auto`, `rtx`, `map` or `addon`. The player can choose your sky by it
  (`nativeloader_sky_here <id>`), so make it unique to your package (`construct_hd_sky`).
- `data_static/*.json` is on GMod's add-on whitelist, and the file is content: no code runs.

```json
{
  "version": 1,
  "title": "Construct HD",
  "sky": "skybox",
  "skyname": "construct_hd",
  "skybox3d": true,
  "default": true,
  "priority": 0
}
```

| Field | | |
|---|---|---|
| `version` | required | `1` |
| `sky` | required | `"map"`: the map's own sky, its sky textures as the map names them (`skyname` in its worldspawn), which your Remix mod may replace by their hashes. `"skybox"`: another skybox, `materials/skybox/<skyname><side>.vmt` (sides `rt`, `lf`, `bk`, `ft`, `up`, `dn`; the game also looks for `<skyname>_hdr<side>`), which your add-on ships |
| `skyname` | with `"skybox"` | The skybox's name, as `sv_skyname` takes it: letters, digits, `_`, `-` and `/`, at most 64. Its faces must be there, or the file is left out |
| `title` | optional | The name the chat line and the panel give your sky ("This map shows the sky of Construct HD."), at most 64 bytes; the id when left out |
| `skybox3d` | optional | `true` (default): the map's 3D skybox shows with your sky, where the map has one at scale 16. `false`: the 2D sky alone |
| `default` | optional | `true` (default): your sky shows on the map unless the player chose another. `false`: it is only offered in the panel's "This map" list |
| `priority` | optional | -100 to 100, default 0. With several files for one map the higher one comes first, then by id |

What the companion does with it:

- **`"map"`**: `rtx.skyMode 0`, so Remix draws the map's sky textures, and the map's own sun (its `light_environment`)
  lights it; the map's 3D skybox with it (`r_3dsky 1`, the map drawn by the PAS while it shows). Ship replaced sky
  textures in your Remix mod as usual; mind that at `mat_hdr_level 2` the game draws a map's HDR faces, whose hashes
  differ from the LDR ones (the `remix-map-pbr` skill's lessons, "A station in orbit").
- **`"skybox"`**: the same, with the 2D sky changed to yours through `sv_skyname`. `sv_skyname` is every player's, so
  this happens only in a single-player game; in any other game your file is skipped and the next one counts.
- **Left out, named in the console** (`[nativeloader] sky: <file> left out: <why>`): a file over 16 KiB, more than 8
  files for one map, a wrong id, version or field, a `skyname` whose faces are not there.

Check it in the game: `nativeloader_sky_status` prints what the map shows, why, and the sky files it read
(`sky files construct_hd_sky(skybox construct_hd)`); `nativeloader_sky_here <id>` chooses your sky,
`nativeloader_sky_here auto` gives the player's default back.

## A Lua add-on that sets the sky

A remaster whose add-on sets Remix's sky options itself (a time of day of its own, a sun as a Remix API light) tells
the companion so, from the moment its Lua loads on that map (the companion decides at `InitPostEntity`):

| Hook or function | |
|---|---|
| `hook.Add("NativeLoaderSkyOwner", ...)` returning your name | The map's sky is yours: the companion sends no sky, sun or weather while it is ([ADR 0031](decisions/0031-physical-sky-time-and-weather.md)) |
| `hook.Add("NativeLoaderSkyFixed", ...)` returning `true` | Your sky is fixed, such as space, so no time of day or weather fits it: it stays also when the player chose their own time ([ADR 0248](decisions/0248-a-maps-add-on-keeps-a-fixed-sky.md)). Without it, the player's own time ("Follow the map's sun" unticked) replaces your sky from the map's start ([ADR 0105](decisions/0105-the-players-sky-applies-from-a-maps-start.md)) |
| `NATIVELOADER_SKY.takenOver()` | `true` once the player's sky replaces yours: they chose another sky for the map, or changed a sky or weather setting in the session. Set your sky only while it is `false`; when it turns `true`, remove what would double the companion's sky (an API sun). It calls no owner hook, so you may ask it from your answer to `NativeLoaderSkyOwner` |
| `hook.Run("NativeLoaderSkySet")` | Run it after you set your sky again: a player's sky that replaced yours goes back at once |
| `NATIVELOADER_SKY.mapSky()` | What the map shows now: `shown` (`rtx`, `own`, `addon` or `taken`), `sky`, `reason`, `threeD`, `package`, the player's `choice` |

An add-on that is not in reach of the companion (an older companion, a game without the RTX package) falls back to its
own sky. A player who switches back to your sky during the session sees it from the next map start, when you set it.

## What the player sees

- **The chat line**, once at the map's start: "[RTX] This map shows the sky of Construct HD. For the RTX sky: type
  nativeloader_sky_here rtx in the console, or use RTX Remix > Sky and weather in the spawn menu." (in the player's
  language), or that the map shows the RTX sky and has its own (with a 3D skybox, or none to switch to).
- **RTX Remix > Sky and weather**: what the map shows; This map (Automatic, RTX sky, The map's own sky, Sky of <your
  title>), remembered for the map; Other maps; Say which sky shows.
- **Time of day, weather and the night sky** belong to the RTX sky: changing one on a map that shows your sky shows the
  RTX sky until the next map starts (ADR 0248, kept for every sky by the user's choice).

## Limits

- A 3D skybox shows only at scale 16 (the runtime's reprojection is set for it, `rtx.skyReprojectScale` in the
  package's layer, which Lua cannot change); at another scale the map's 2D sky shows alone, and the panel says so.
- While a map's 3D skybox shows, the map is drawn by the PAS, as the original game draws it around the camera.
- Under the RTX sky the whole map is drawn, and a 3D skybox room in view (gm_construct's, overhead) shows as a small
  copy; a remaster can draw its map by the PAS (the `remix-map-pbr` skill) or hide the room's props.

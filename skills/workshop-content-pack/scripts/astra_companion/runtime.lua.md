# runtime.lua

The client runtime of every add-on [`astra_companion.py`](../astra_companion.py.md) makes from a map's
former Astra companion. The converter copies it unchanged into `lua/<addon>/runtime.lua`; the add-on's
autorun file includes it on its map only and calls the function it returns with the add-on's profile
(`profile.lua`) and folder. It replaces the companions' bridge runtime: no `AstraRTXBridge`, no
startup report, no batches; the PBR materials are the Remix mod the native loader deploys.

## What it does on the map

| When | What |
|---|---|
| the file loads, `Initialize`, `InitPostEntity` | the profile's engine convars (`rtx_api_map_lights_autospawn 0`), saved first, so Light2RTX does not add the map's `light_environment` as a second sun (its autospawn runs 1.5 s after `InitPostEntity`) |
| 3 s after `InitPostEntity` (the start) | `Light2RTX.Clear()`; the profile's lights through `RemixLight.Create*`; the Remix options (`RemixConfig.SetConfigVariable`, each one's restore value saved first); `$color`/`$color2` to white on the profile's materials; the base map's stand-in hooks removed; Remix hash categories on the hashes of the profile's materials; one log line with the counts |
| 20, 40 and 60 s after the start | the engine convars, the options and the tints again (other add-ons finish their map setup over the first minute) |
| every 2 s, at most 30 times | hash categories of materials not drawn yet (no texture hash until the first draw), until all are found |
| `ShutDown` | lights destroyed, options put back in reverse order, convars put back, categories released, hooks re-added, the shell's mesh destroyed; the tints stay (map-only materials; a material changed in `ShutDown` can crash the map change) |

Only the shell runs per frame: with a `shell` in the profile, one `PostDrawOpaqueRenderables` hook
(`<addon>_shell`) draws a 24-triangle mesh. No `Think`, `Tick`, HUD or other render hook (the harness
checks it). The companions it replaces deep-copied their whole status, 176 materials with their hash
lists, in two `Think` hooks every frame and in their 4 Hz timers.

- **The shell.** An Astra map is a mesh inside a BSP that is only a skybox box around it, and the
  mesh is closed only where the Blender scene's cameras looked: the Korolevskiy Theater has no ground
  beside and under its stage. A camera in such a gap (noclip) sees the skybox, which Remix renders as a
  lit sky: the theater's uniform navy came out as a bright lavender sheet. At the start the runtime
  builds a box from the profile's `min` to `max`, each face with both windings and its normal facing
  in, and draws it with `materials/<addon>/shell` in the main view; the depth pass and the 3D skybox
  are skipped, but not the hook's second argument, which is true in the main view whenever the 2D sky
  shows (every frame there, measured in the field game on 2026-11-09: a shell that skipped it never
  drew). Without the material it logs that and runs without the shell. It goes at `Stop` (the map's
  end, `<prefix>_enable 0`, a reload).

- **Restore values.** `RemixConfig.GetConfigVariable` reports `rtx.conf`, not the live value, so an
  option goes back to the player's `rtx.conf` value, else the profile's default (the RTX package's
  Remix defaults layer, else the runtime's own), as Modern House RTX does.
- **The game's own lights** (`rtx.ignoreGame*`) are hidden only while this add-on's lights exist.
- **Whose sky.** With `sky_owner` it answers the companion's `NativeLoaderSkyOwner` hook, so the RTX
  package's physical sky leaves the map's own sky alone (ADR 0031), and runs `NativeLoaderSkySet` after
  each pass of options. When the player chose their own sky (Follow the map's sun off at the start, or
  any `nativeloader_sky*`/`nativeloader_weather` setting changed in the session, ADR 0105; not the hour
  and direction, which the companion writes itself while following the map, and whose change by the
  player switches Follow the map's sun off) and the companion's physical sky is on, the companion is in
  charge. The settings are watched from `InitPostEntity` on: the add-on's autorun runs before the
  companion's, and GMod sets a Lua convar's saved value right after creating it at its default, which a
  callback added earlier sees as a change (the PoC's saved `clear` weather took the sky over that way
  until 2026-11-09). Then: the scene's distant lights and the
  profile's `sky_keys` stay out, so there is never a second sun; switching the companion's sky off
  (the map's skybox) brings them back.
- **The haze.** With `fog_owner` it answers `NativeLoaderRemixFogOverride` while it runs, so the
  companion's weather leaves `rtx.volumetrics.*` to the map, whoever drives the sky.
- **Categories.** A hash already carrying the flag is left as it is and not released; on release the
  API removes a hash's whole set, so whatever else the hash had is set again.

## Console

| | |
|---|---|
| `<prefix>_status` | running or not; lights (failed, suns); options (refused ones by name); whose sky; tints, stand-ins, hash tags, materials not drawn yet, the shell (closed and how often drawn, or open); the mod's coverage: per material of `hashes.lua`, whether the texture hashes uploaded so far are the ones the mod replaces |
| `<prefix>_enable 0/1` | archived; 0 stops everything and puts the tints back, 1 starts again |
| `<prefix>_reload` | stop and start |

A Lua reload of the file stops the old runtime and starts the new one at once.

## Requirements

GMod RTX with the RTX fixes' Lua API: `RemixLight`, `RemixConfig`, and for categories and the coverage
check `RemixMaterial` (`GetAllTextureHashes`, `GetHashCategory`, `SetHashCategory`,
`RemoveHashCategory`). Without `RemixLight` or `RemixConfig` it logs that and does nothing. The
package's `requires_remix` hides the add-on in starts without RTX anyway.

Tests: [`../astra_companion_harness.lua`](../astra_companion_harness.lua.md) through
[`../test_astra_companion.py`](../test_astra_companion.py.md).

# astra_companion_harness.lua

Runs an add-on made by [`astra_companion.py`](astra_companion.py.md) (its autorun file, `runtime.lua`,
`profile.lua`, `hashes.lua`) against mocked GMod and Remix APIs in LuaJIT: hooks, timers (stepped by
hand), convars with change callbacks, console commands, materials with `$color` vectors, `Mesh` and
`mesh.*` (vertices recorded, draws counted), `render.SetMaterial`, `RemixConfig` with an `rtx.conf`,
`RemixLight`, `RemixMaterial` categories and texture hashes, `Light2RTX`.

```
luajit astra_companion_harness.lua <add-on folder> <scenario>
```

| Scenario | Checks |
|---|---|
| `lifecycle` | nothing reaches Remix before the start; the sky owner answers; the start creates every light, sets every option, runs `NativeLoaderSkySet`, neutralises tints (white ones untouched, recompute once), removes the stand-in hooks, tags the drawn materials' hashes and retries the rest until found; three re-applies in the first minute, then none; no per-frame hook at any point but the shell's; the status prints the mod coverage; `ShutDown` destroys the lights, puts every option back (to `rtx.conf`'s value, else the profile's default), puts the convar and hooks back, releases the tags (another producer's tag on the same hash survives) and changes no material |
| `other_map` | on another map: no global, no hook, no convar touched |
| `no_remix` | without the Remix API: no start, and it says so |
| `disable` | `<prefix>_enable 0` stops everything, puts the tints and convars back and gives the sky back; 1 starts again |
| `reload` | loading the file again stops the old runtime and starts the new one, with no doubled lights |
| `player_sky` | the player's own sky before the map (the companion's sky on, Follow the map's sun off): no scene sun, no `sky_keys`, the other lights there; the haze stays the map's while it runs, not after |
| `shell` | (a profile with a shell) the add-on ships the shell's `.vmt` and `.vtf`; the start builds one mesh of 24 triangles whose vertices are the box's eight corners, each normal facing in; it is not drawn in the depth or 3D skybox passes, but is in the main view, also when the hook's second argument (the 2D sky) is true, with the shell's material; the status counts the draws; `<prefix>_enable 0` and a reload replace it, `ShutDown` destroys it; without the material the map starts without a shell and says so |
| `sky_takeover` | a saved value set before the map's start, a set to the same value and the companion's own writes of the hour and direction (following the map) keep the map's sky; Follow the map's sun switched off hands it over (the suns go, `sky_keys` are not set again); the companion's sky switched off brings the suns and `sky_keys` back |

Prints `PASS <scenario>` and exits 0, or exits nonzero with the failed check. Reads only the add-on
folder. Run by [`test_astra_companion.py`](test_astra_companion.py.md) on a converted synthetic
companion; run it by hand on a real build's `addon\<addon>` folder too.

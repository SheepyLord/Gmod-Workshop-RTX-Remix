# light_updater_harness.lua

Loads the RTX fixes' light updater (GPL, `packages/fixes`, `cl_rtx_light_updater.lua`) under a fake GMod API
and checks which helpers a frame draws since R28
([ADR 0144](../../docs/decisions/0144-the-light-updater-draws-what-the-runtime-needs.md)). The fake map is a
row of forty plain `light` entities, one every 256 units, each with its point world light; a scenario adds to
it. Walls are planes across the row that stop a trace; the sky is seen from above a height. The harness sets
`rtx_lightupdater_all -1`: the default, 0, uses the list only on maps with 256 lights or more.

| Scenario | What it checks |
|---|---|
| `bounded` | Every helper is drawn on the first two frames and while its lights are being worked out; then only the lights ahead of the eye and the one within 450 units behind it; turned round, the others, with those now behind held for two frames; each helper out of view has its turn within 120 frames; `rtx_lightupdater_all 1` draws all again, `0` too on this map of forty lights (the status says the map has fewer than 256), `-1` uses the list |
| `dynamic` | A `gmod_light` behind the eye keeps the lights within 450 units of it drawn every frame; so does a light made with `DynamicLight`, where it is and where it moves to, until a dozen frames and the hold after its last call. The harness hands such a light out as the game does: a fresh object per call whose fields can be written, not read, so the position is noted as it is written. With `entity` the object cannot be watched and the entity the light is keyed by stands for it |
| `texture_light` | A texture light beside light 5: that helper and its two neighbours are drawn every frame with the eye looking away; helpers far along the row are not. With `walls`, a far helper that has only three steady lights in sight is drawn every frame as well. With `strong` the texture light outshines the neighbours of helpers ten lights away, which are then drawn every frame; with `pvs` the map has visibility data in which a cluster of ten lights sees itself alone, and only the helpers of the texture light's own cluster are; with `solid` the far helpers' spots are in no cluster, where the engine takes every light, and they are drawn every frame again |
| `spot_and_switched` | A `light_spot` and a named, styled light keep their own helpers every frame; each of those helpers is found to set its light, so the steady lights beside them are bounded like the rest, also with only three steady lights in sight (`walls`). With `dim` the spot light is too dim to be among the two strongest where its own helper stands: the steady light beside it is drawn every frame, and the status counts one light set by its own helper and one with none |
| `light_set_by_a_neighbour` | A dim light between two far stronger ones is not among the two strongest where its own helper stands: the neighbours' helpers are drawn while it is in view, and nothing when it is not. With `bright` its own helper sets it and the neighbours' are not drawn |
| `sky` | With a sun among the world lights, the helpers that see the sky are drawn every frame, those indoors are bounded |
| `options` | `rtx.antiCulling.light.enable = False` in `rtx.conf`: every helper every frame, and `rtx_lightupdater_status` says why. With `frames`, a lifetime of 200 frames brings every turn round within 50 |
| `no_world_lights` | No world lights, world lights that are not where the light entities are (`mismatch`), or an emit type outside 0-5 (`layout`): every helper every frame, and the status says so |
| `rebuild` | A `gmod_light` appears: every helper is drawn for the two frames of the rebuild, then the list is bounded again at once, with no new trace for the map's lights |

Usage: `luajit tools/tests/light_updater_harness.lua <cl_rtx_light_updater.lua> <scenario> [variant]`. Reads
only the given file; no game, network or file writes. Exit 0 and a `PASS` line on success, nonzero on a failed
assertion. Run by [test_light_updater.py](test_light_updater.py.md).

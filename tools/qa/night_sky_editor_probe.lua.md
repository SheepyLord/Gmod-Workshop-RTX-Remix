# night_sky_editor_probe.lua

A client Lua probe for the Night sky editor ([ADR 0227](../../docs/decisions/0227-the-night-sky-editor.md)), run by
[`poc_session.py`](../poc_session.py.md) `run --lua tools\qa\night_sky_editor_probe.lua --lua-shots 300` in an RTX
session of the PoC. It holds a clear midnight with a full moon (weather `clear` at once, the clock stopped, 00:00) and
changes each element of the night sky on its own, taking the same views after each step:

| Step | What changes |
|---|---|
| `default` | every editor setting at its default |
| `constellations0` | the constellations' bright stars hidden (their texture freed) |
| `constellations6white` | the constellations six times as bright, colour 0 (white) |
| `stars4grey` | constellations back; the stars four times as bright, grey |
| `milkyway_alone4` | the stars, constellations and nebulae hidden, the Milky Way four times as bright |
| `nebulae_alone4` | the nebulae alone, four times as bright, colour 1.5 |
| `all_off` | every layer hidden: a night without stars (moon, airglow, shooting stars) |
| `image3` | every layer back, the whole image three times as bright |
| `moon_default` | the moon where it stands (40 degrees of view), as by default |
| `moon_big` | the moon 4 degrees across, twice as bright, glow 3 |
| `reset` | `nativeloader_sky_night_reset` |
| `stars_default` | the defaults again, through a narrow view |
| `stars4` | the stars four times as bright |
| `stars0` | the stars hidden |
| `stars2grey` | the stars twice as bright, colour 0 (grey) |

Views (a `CalcView` hook from a place under open sky near the spawn, found with traces; HUD and view model hidden): the
zenith at 110 degrees of view, and 45 degrees up to the east and the west at 90; the moon's steps look at the moon. At
1280x720 a pixel of those wide views spans 14-17 texels across of the star layer (about 200 a degree), whose small
stars then average into a faint haze, so the last four steps look through 35 degrees (70 degrees up, about 5 texels a
pixel), where single stars show.
Each screenshot is asked for with `NL_SHOT <step>_<view>` 2.5 s after the view (1.5 s after a step's change, which
may load a texture), and the next follows the driver's `nl_shot_taken`. After each step it runs
`nativeloader_sky_status`, so the console has the editor's values. Prints `NL_NIGHT place` and `NL_NIGHT kept` (the
player's archived sky and editor settings), and puts those back before `NL_SHOT_DONE`.

**Needs:** an RTX session with the companion's sky (`NATIVELOADER_SKY`) and runtime patch 0099. **Side effects:** the
session's time, weather and editor settings, put back at the end. **Exit:** none (a Lua file); the driver's record has
the screenshots.

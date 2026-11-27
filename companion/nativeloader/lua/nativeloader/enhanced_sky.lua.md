# enhanced_sky.lua

Drives the Enhanced RTX sky through the companion's Remix option writer. The
[Sky and weather autorun](../autorun/nativeloader_sky.lua.md) supplies its sky model, cached setter and
configuration reader once. It selects the provider after resolving map ownership and the current VR session.

The controller takes the current sun and Moon, clock, season, map north, weather, transition length and quality.
It sends the NUMOS options under `rtx.atmosphere.numos.` and requests sky mode 2. The runtime's
`volumetrics` option selects Enhanced mist or a handoff from nearby Remix fog to distant Enhanced mist.
It drives a single library Moon with the companion's positions and the library's lunar surface. The clock also
supplies the date and time for the star catalogue. A lunar eclipse uses the geometric phase.
On first use per map it sends `worldChangeCount` so NUMOS measures the ground of the new world.

The [weather data](enhanced_weather.lua.md) supplies the endpoints. A change blends from the current weather,
including during a previous transition. Wind bearings take the short arc. Fog interpolates in extinction.
A cloud layer appears or clears at its own height. The fog choice on the Remix settings page takes precedence
over the weather's visibility, albedo and anisotropy. In handoff mode the controller also converts the current
look's 2% contrast distance back into Remix transmittance and measuring distance, scattering albedo and anisotropy.
Precipitation remains with the autorun. Rainbows take their water from drizzle, rain and thunderstorms, then
dry out over 300 game seconds. The [editor](enhanced_editor.lua.md) can replace a weather's appearance and
blend from the currently displayed sky over two seconds.

Automatic detail reads the loader's schema-1 `native-loader/status.json` in `DATA` on first use. High, Medium
and Low select 0, 1 and 2. An absent or unrecognised tier selects Medium. Night gain and lamp limits apply even
with weather left to Remix. A pending round 1 `nativeloader_sky_volumetrics_saved` is restored once and cleared.
The player's global volumetrics switch then stays under their control.

The controller writes runtime options and the session convar. It has no command or exit code. Its offline
tests run in [test_companion_sky.py](../../../../tools/tests/test_companion_sky.py.md).

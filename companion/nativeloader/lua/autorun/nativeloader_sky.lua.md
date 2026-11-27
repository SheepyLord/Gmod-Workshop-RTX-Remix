# nativeloader_sky.lua

**Enhanced sky.** Under RTX Remix → Sky and weather, **Sky quality** selects Enhanced (the default since the
user's word of 2026-11-26) or Standard. `nativeloader_sky_enhanced` saves that choice as 1 or 0. **Enhanced detail** saves
`nativeloader_sky_enhanced_quality` as `auto`, `high`, `medium` or `low`. Both choices apply to the
companion's RTX sky under ADR 0249. A fixed add-on, a sky file and the map's own sky retain their priority.
VR uses Standard for the session and the desktop preference resumes afterwards.

[The Enhanced controller](../nativeloader/enhanced_sky.lua.md) translates the clock, Moon and weather controls.
[The weather tables](../nativeloader/enhanced_weather.lua.md) are the tuning surface for the twelve looks.
Round 2 adds the [Enhanced sky editor](../nativeloader/enhanced_editor_panel.lua.md) beside the Night sky
editor. Both skies follow the Night sky editor's Moon size and brightness. Enhanced maps brightness to disc
gain in stops and supplies a separate moonlight control for the ground. The horizon switch, solar eclipse
and the remaining night editor layers are Standard features. `nativeloader_sky_status` reports the NUMOS
quality level while Enhanced is active.

ADR 0249: **which sky a map shows** (the user's request of 2026-11-20). The RTX sky by default on every map; the
map's own sky (its sky textures and, at scale 16, its 3D skybox) chosen and remembered per map (`nativeloader_sky_here`,
"This map"); `nativeloader_sky` the default for other maps ("Other maps"); above the RTX sky the sky a map's RTX version
brings: its add-on's (the hooks below) or a sky file in `data_static/nativeloader/sky/<map>/<id>.json`
([docs/MAP_SKY.md](../../../../docs/MAP_SKY.md)); one chat line at the map's start says which sky shows and how to
switch. [`map_sky.lua`](../nativeloader/map_sky.lua.md) decides; this file reads the map, the files and the choices and
does it (see "Which sky a map shows").

ADR 0227: **the Night sky editor**, a page of its own beside "Sky and weather" in the RTX Remix tab, sets how each
element of the night sky looks: the night sky image's four layers (stars, the constellations' bright stars, the Milky
Way, the nebulae), each a brightness and a colour; the simulated stars; the moon's brightness, size, glow and
earthshine; the shooting stars; the night's glow between the stars. They send the runtime's options of patch 0099
([ADR 0227](../../../../docs/decisions/0227-the-night-sky-editor.md)) and some older ones (see "The night sky editor").
Like No horizon they are how the player sees whichever physical sky is shown: changing one does not take a map's sky
over.

ADR 0207: **Moon by day** (`nativeloader_sky_moon_day`, 1 by default, 0-4), a slider under Moon. It sends
`rtx.atmosphere.daytimeMoonBrightness`, the runtime's option of patch 0090
([ADR 0207](../../../../docs/decisions/0207-the-moon-by-day.md)): while the sun is up the moon's light is added to the
sky in front of it, as bright as the real Moon at its phase at 1, so a first-quarter moon stands as a pale disc in the
afternoon sky and a crescent shows faintly near the sun; 0 hides the moon by day, as before. The night's moon is not
changed by it (see "The moon by day").

R26: **No horizon** (`nativeloader_sky_no_horizon`, off by default), a checkbox under Sky, for maps
that float in the sky or in space. It sends `rtx.atmosphere.noHorizon`, the runtime's option of patch
0041 ([ADR 0139](../../../../docs/decisions/0139-the-sky-without-a-horizon.md)): below the horizon the
physical sky goes on instead of the even haze of a ground, with clouds, the stars and the moon (see
"The horizon"). It is how the player sees whichever physical sky is shown, not whose sky it is: it
also reaches the sky of a map's own add-on, and changing it does not take that sky over (see "A map
whose add-on sets the sky").

R20-B: Time passes defaults on and a day lasts 20 real minutes. The defaults autorun migrates only
the untouched old `0`/`30` pair once, before this file installs callbacks or starts its clock
([ADR 0117](../../../../docs/decisions/0117-startup-upscaling-hint-and-sky-defaults.md)). Reset uses
`1`/`20` too. The slider remains 2–240 minutes; 20 is within that range. A map's starting sun and
R16's sky-add-on ownership rules below are preserved.

R14-H rewords four help lines of the Sky and weather panel (Follow the map's sun, Day length, Sky
update interval, Weather) in the guide's terms; the controls and their behaviour are unchanged.

Common Remix fog presets take precedence only when the menu's `NativeLoaderRemixFogOverride` hook
returns true, after a preset was applied in this session. An archived draft with startup replay off
does not suppress the weather's fog (ADR 0044).

The sky in RTX sessions ([ADR 0031](../../../../docs/decisions/0031-physical-sky-time-and-weather.md),
[ADR 0032](../../../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)).
The runtime has a physical sky that the RTX fixes leave off: `rtx.skyMode 1`, with scattering,
volumetric clouds, stars and moons. This file turns it on and drives it:

- the sun, the moon and the stars for a time of day, by default the time and direction of the map's
  own sun;
- a clock that can run;
- the moon's phase, and lunar and solar eclipses;
- the night sky image (the runtime's Night Sky HD LE layers: stars, galaxy, nebulae) or the procedural stars;
- the runtime's twelve weather presets, blended into each other.

Everything reaches Remix through the RTX fixes' `RemixConfig.SetConfigVariable`, which writes Remix's
user layer, as the "Remix settings" panel does. Shared autorun: the server only sends this file,
[`sky_model.lua`](../nativeloader/sky_model.lua.md) (the arithmetic) and
[`weather_presets.lua`](../nativeloader/weather_presets.lua.md) (the presets) to clients.

## Settings

Saved client settings, shown in the RTX Remix tab under "Sky and weather":

| Setting | Default | What |
|---|---|---|
| `nativeloader_sky` | `1` | The sky of maps without a choice of their own ("Other maps"): 1 the RTX sky (the physical sky); 0 their own sky, with its 3D skybox (ADR 0249). A map's RTX version's sky comes first. Changing it takes no map's sky over |
| `nativeloader_sky_here` | `auto` | This map's sky ("This map"), not saved itself but remembered per map in `data/nativeloader_companion/sky_maps.txt` (one `<map> <choice>` a line; `auto` is not written) and set from it at each map's start: `auto`, `rtx`, `map`, `addon` or a sky file's id (ADR 0249) |
| `nativeloader_sky_message` | `0` | One chat line at a map's start says which sky shows and how to switch ("Say which sky shows"); off by default (ADR 0253; a saved copy of the earlier default, on, goes off once: `nativeloader_defaults.lua`); the console gets it in English either way |
| `nativeloader_sky_no_horizon` | `0` | 1: the physical sky has no horizon: the sky goes on below it, with clouds, the stars and the moon (R26). Changing it does not take a map's sky over |
| `nativeloader_sky_follow_map` | `1` | The time and the sun's direction come from the map's own sun |
| `nativeloader_sky_hour` | `14.5` | Time of day, 0-24. Following the map, it shows the map's time |
| `nativeloader_sky_direction` | `0` | Turns the sun's path around the sky (the map's north bearing), in degrees |
| `nativeloader_sky_time_passes` | `1` | The clock runs |
| `nativeloader_sky_day_minutes` | `20` | Real minutes for a whole day while the clock runs |
| `nativeloader_sky_season` | `summer` | `spring`, `summer`, `autumn`, `winter`: how high the sun climbs and how long the day is |
| `nativeloader_sky_moon` | `full` | Moon phase: `new`, `waxingCrescent`, `firstQuarter`, `waxingGibbous`, `full`, `waningGibbous`, `lastQuarter`, `waningCrescent` |
| `nativeloader_sky_moon_day` | `1` | The moon by day, 0-4: 1 is as bright as the real Moon at its phase, 0 hides it while the sun is up (ADR 0207) |
| `nativeloader_sky_eclipse` | (empty) | `lunar` or `solar`; empty for none. An eclipse sets the moon's phase (full, new) |
| `nativeloader_sky_eclipse_amount` | `100` | How far through the eclipse, 0-100: first contact to the middle; lunar total from 70, solar from 90 |
| `nativeloader_sky_stars` | `map` | Night sky: `map` (the night sky image: stars, galaxy and nebulae) or `procedural` |
| `nativeloader_weather` | `partlyCloudy` | One of the twelve presets (`clear`, `partlyCloudy`, `overcast`, `hazy`, `foggy`, `drizzle`, `rainstorm`, `thunderstorm`, `snow`, `blizzard`, `sandstorm`, `smoggy`); empty leaves clouds, fog and rain to Remix's files (see "Weather left to Remix") |
| `nativeloader_weather_seconds` | `30` | How long a change of weather takes |
| `nativeloader_sky_interval` | `0.02` | Seconds between updates of the sun, moon, stars and weather, 0-1: 0.02 is 50 a second, 0 every frame. Changing it does not take a map's sky over (R3-015) |

The Night sky editor's settings (ADR 0227), on its own page beside "Sky and weather". Each is held to its range (text
that is not a number counts as the default), and none takes a map's sky over:

| Setting | Default | Range | Sends | At 1 (or the default) |
|---|---|---|---|---|
| `nativeloader_sky_night_image` | `1` | 0-4 | `rtx.atmosphere.starMapBrightness` | 0.12: the whole image |
| `nativeloader_sky_stars_brightness`, `_colour` | `1` | 0-8, 0-2 | `starMapStarBrightness`, `starMapStarSaturation` | the image's stars |
| `nativeloader_sky_constellations_brightness`, `_colour` | `1` | 0-8, 0-2 | `starMapConstellationBrightness`, `...Saturation` | the constellations' bright stars |
| `nativeloader_sky_milky_way_brightness`, `_colour` | `1` | 0-8, 0-2 | `starMapGalaxyBrightness`, `...Saturation` | the galaxy band |
| `nativeloader_sky_nebulae_brightness`, `_colour` | `1` | 0-8, 0-2 | `starMapNebulaBrightness`, `...Saturation` | the nebulae |
| `nativeloader_sky_simulated_brightness` | `1` | 0-4 | `rtx.atmosphere.starBrightness` | 0.5, the runtime's |
| `nativeloader_sky_simulated_density` | `0.5` | 0-1 | `rtx.atmosphere.starDensity` | the value itself |
| `nativeloader_sky_simulated_twinkle` | `1` | 0-4 | `rtx.atmosphere.starTwinkleSpeed` | 1, the runtime's |
| `nativeloader_sky_moon_brightness` | `1` | 0-4 | `rtx.atmosphere.moon0.brightness` | the disc and its light on the map |
| `nativeloader_sky_moon_size` | `1.6` | 0.5-5 | `rtx.atmosphere.moon0.angularRadius` (degrees across) | see "The night sky editor" |
| `nativeloader_sky_moon_glow` | `1` | 0-4 | `rtx.atmosphere.haloMoonBrightness` | 15, the runtime's |
| `nativeloader_sky_earthshine` | `1` | 0-8 | `rtx.atmosphere.moon0.darkSideBrightness` | 0.005, the runtime's |
| `nativeloader_sky_shooting_stars` | `1.2` | 0-15 | `rtx.atmosphere.shootingStarsPerMinute` | the value itself |
| `nativeloader_sky_shooting_star_brightness` | `1` | 0-8 | `rtx.atmosphere.shootingStarBrightness` | the runtime's |
| `nativeloader_sky_night_glow` | `1` | 0-4 | the weather's `nightSkyBrightness` times this | the weather's airglow |

Moving the time or the direction turns `nativeloader_sky_follow_map` off. The other one keeps the
map's value, which the panel shows.

- **The panel's sliders write back what they show.** The direction slider has no decimals and the
  time slider two. While the sky follows the map, a value within that rounding of the map's own counts
  as the companion's, not the player's.
- **Values the companion writes itself** (the map's time and direction, the time a stopped clock
  reached) do not count as the player's either.
- **Choosing an eclipse** with the sun on the wrong side of the horizon for it (higher than 8 degrees
  below it for a lunar one, lower than 15 degrees up for a solar one) sets the time to 00:00 or 12:00,
  and so turns `nativeloader_sky_follow_map` off.

## What it gives Remix

### The sky

With the physical sky on (`nativeloader_sky 1`):

- `rtx.skyMode 1`.
- `rtx.ignoreGameDirectionalLights True`: the map's sun reaches Remix as a fixed-function light, and
  in this mode the atmosphere makes the sun.
- `rtx.atmosphere.timeCycleEnable False`: the runtime's own clock moves only the sun.
- The look (`LOOK`):
  - moon 0 on, a touch cool, by default 1.6 degrees across instead of 3.5 (the Night sky editor's moon size). The
    moonlight scales with the disc's area, so the ground light (`surfaceMoonBrightness`) is raised from 50 to 240 to
    make up for the smaller disc, and for another size by (1.6 / size)^2, so the size changes how the moon looks, not
    how light the night is. It fades in with the twilight, from none with the sun 4 degrees down to all of it at
    12. The runtime lights the ground fully as soon as the sun is down, which lit the towers orange
    from a rising moon at dusk;
  - the cumulus-shaped cloud shadows on the ground (`cloudVoxelShadowsEnable`), which the classic
    install's settings, and so the package's Remix defaults, turned off;
  - the real Moon's face (`moonTextureEnable True`, the runtime's default too), its relief at 0.6
    (`moonReliefStrength`; at the runtime's 1 the terminator broke into dark notches when zoomed in);
  - eclipses on, with the shadow and sun scales the eclipse stages assume (`eclipseEnable`,
    `eclipseUmbraScale 2.65`, `eclipsePenumbraScale 4.8`, `eclipseSunScale 0.97`, from
    `sky_model.ECLIPSE`).
- `rtx.atmosphere.starMapEnable`: `True` for the night sky image (`nativeloader_sky_stars map`),
  `False` for the procedural one.
- `rtx.atmosphere.daytimeMoonBrightness`: the Moon by day (`nativeloader_sky_moon_day`, held to 0-4).

With the map's own sky (ADR 0249: chosen for the map, a sky file's, or `nativeloader_sky 0` on a map without a choice):
`rtx.skyMode 0`, sent again with everything else (an add-on may have changed it), and
`rtx.ignoreGameDirectionalLights` back to its `rtx.conf` value (`False` if none), so the map's own sun lights it. The
weather is the RTX sky's: what it had set goes back to Remix's own values (see "Weather left to Remix"), and no clock,
sun or weather is sent.

### The map's own 3D skybox (ADR 0249)

Where the map's own sky shows and the map has a 3D skybox (a `sky_camera`) at scale 16, and the sky file, if any, does
not say `"skybox3d": false`:

| Convar | Set to | Why |
|---|---|---|
| `r_3dsky` | `1` | The engine's sky camera pass, which the session turns off. The runtime moves what it draws out to the main camera at `rtx.skyReprojectScale` (17 in the package's layer, for scale 16, a touch further out so a copy of the playable area stays behind the map) and path traces it |
| `r_novis`, `rtx_patch_forcenovis`, `rtx_patch_vis_pas` | `0`, `0`, `1` | Visibility by the PAS (the RTX fixes' patch). With the session's whole-map drawing the sky pass drew the whole map too, magnified 16 times around the camera; by the PAS it draws the skybox room alone, and the main view what the original game draws around the camera, without the skybox room's miniature |

- `r_3dsky 1` goes out between `rtx_show_3dsky_warning 0` and its old value, all three as console commands in that
  order, so the RTX fixes' question before `r_3dsky 1` (`cl_rtx_settings.lua`, a change callback that runs with the
  command) is held back for this change. The engine's convars go out as console commands; the fixes' patch switches,
  convars made in Lua, change at once (`SetString`), and `RTX_SyncPatches` applies them 0.1 s later.
- Before the first change their values are recorded in `nativeloader_sky_engine_saved` (`name=value;...`, not saved).
  When the 3D skybox goes (another sky, a setting changed, the next map's start) they are put back and the record
  cleared. At `ShutDown` (a level change, a quit) they are put back too but the record stays, since a command sent
  while the map unloads may not run: the next map's start checks them again.
- The companion's file path names `nativeloader`, so the RTX guard lets it change these session pins; other Lua still
  cannot.
- They are set at the map's start, again 1.5 s later (the RTX fixes' per-map settings set `r_3dsky 0` a second after
  the start) and with everything at 5 s; not on a timer after that, so a remaster that keeps `r_3dsky 0` for its map
  (gm_stelliferous RTX) is not fought.
- At another scale (gm_stelliferous 64, gm_construct_renovation 32) the map's 2D sky shows alone: `rtx.skyReprojectScale`
  cannot be set from Lua (RemixConfig's allowlist), and at 17 its 3D skybox would land at the wrong distance. The panel
  and `nativeloader_sky_status` say so.

### A sky by its name (ADR 0249)

A sky file of `"sky": "skybox"` shows another skybox: `sv_skyname` set to its `skyname` (the game changes the 2D sky at
once), the map's own name put back when it goes (and at `ShutDown`; the next map sets its own anyway). `sv_skyname` is
every player's, so only in a single-player game; elsewhere such a file is skipped.

### The horizon

`rtx.atmosphere.noHorizon`: `True` with No horizon ticked (`nativeloader_sky_no_horizon 1`), else
`False`. The runtime's option (patch 0041,
[ADR 0139](../../../../docs/decisions/0139-the-sky-without-a-horizon.md)) is for maps that float in
the sky or in space, where the camera sees below the horizon. Off, a direction below it shows the
ground-level air of a planet the map does not have: an even haze under a sharp horizon line, without
clouds or stars, and a moon there is a black disc. On, the sky goes on below the horizon:

- its colours are the mirror image of the sky above, so the haze band at eye level is the sky's own;
- its clouds and high clouds are those of the opposite side above (the antipode's), so they are no
  reflection of the clouds above it;
- everything is lit for the true angle to the sun, so the sun's glow, silver linings and halos stay
  around the sun, and no mirror sun appears below;
- the stars, the galaxy and the moon show where they are, in every direction.

The sun still sets: below the horizon it is night. Reflections and indirect light see the same sky.

It is how the player sees whichever physical sky is shown, not whose sky it is, so it is not part of
the sky a map's add-on can own:

- With the companion in charge it goes out with the rest, at a map's start and on every change.
- On a map whose add-on sets the sky (see below) it is sent too, but only when it is ticked or
  changed: with the setting at its default the companion still sends such a map nothing.
- Changing it does not take that map's sky over, as `nativeloader_sky_interval` does not.

It costs nothing while off. On, the screen's clouds are also marched for the pixels below the horizon,
which costs up to as much again as the clouds above them (at 3840x2160 0.5 ms more in clear weather,
1.2-1.8 ms partly cloudy, up to 3.2 ms overcast); the sky-view LUT is baked once when it changes.

### The sun, the moon and the stars

From the model, at latitude 40, for the clock, the season, the moon phase and the north bearing:

- `rtx.atmosphere.sunElevation`, `sunRotation`;
- `moon0.elevation`, `moon0.rotation`, `moon0.phase`;
- `starRotation`, `starAxisElevation`, `starAxisRotation`.

They are sent at the start of a map, on every change, and every `nativeloader_sky_interval` seconds
(0.02 by default; it was 0.25 until R3-015, and a running clock then moved the sky in visible steps).
An unchanged value is not sent again.

**The moon off the ecliptic.** The runtime draws an eclipse wherever the geometry has one, so the
moon is never quite on the ecliptic:

- **No eclipse:** it passes 5.64 degrees north of it, just clear of Earth's penumbra for its size
  ((4.8 + 1) moon radii + 1 degree, so a larger moon from the Night sky editor passes further off).
  The real Moon passes up to 5.1 degrees off, and so mostly misses the shadow.
- **An eclipse:** the moon is full (lunar) or new (solar), and its distance from the shadow's centre
  or the sun's comes from `nativeloader_sky_eclipse_amount`, by stages. The model's
  `eclipseSeparation` says which.

### The moon by day

The moon stands where its phase puts it: a first quarter 90 degrees east of the sun (rising at noon, high in the
afternoon), a full moon opposite it (rising at sunset), a waning one in the morning sky. Since runtime patch 0090
([ADR 0207](../../../../docs/decisions/0207-the-moon-by-day.md)) the runtime draws it while the sun is up too, as the
real one shows: its light is added to the sky in front of it, so the blue shows through its dark side, and by day it is
as bright as the real Moon at its phase. Against the sky around it (the decision's numbers, partly cloudy, summer) the
lit part of a first-quarter moon at 16:00 is about 40 % brighter than the sky, a waxing gibbous one before sunset about
60 %, a crescent 15 to 30 %; near the horizon's haze and near the sun it all but vanishes, as the real one does.
`nativeloader_sky_moon_day` (`rtx.atmosphere.daytimeMoonBrightness`) scales that light, 0 to 4; 0 hides the moon by day.
As the sun sinks to 5 degrees below the horizon the runtime hands the moon over to the night's look, which this setting
does not change; the moon's ground light (`surfaceMoonBrightness`, above) stays a night light. The runtime also hides a
moon below the horizon now (it showed through the ground's haze), except with No horizon.

### The night sky editor

The Night sky editor's page (ADR 0227) is built by `buildNightPanel` beside the Sky and weather panel, in the same
category. From the top: Go to night (`nativeloader_sky_time night`), Time passes (to hold the night while editing),
the Night sky choice, then the night sky image's layers (all of them, then each layer's brightness and colour), the
simulated stars, the moon, the shooting stars, the night glow, and Reset the night sky. Its help lines say what 1 and
0 mean, that the constellations come out with the first stars while the Milky Way and the nebulae wait for full
darkness, and that a layer at 0 leaves video memory.

What goes to Remix (the table under "Settings"): each setting times the option's value at 1. With the companion in
charge of a physical sky every one goes out with the sky, at a map's start and with everything again; on a map whose
add-on owns the sky only those off their defaults, and the one being changed, so a player who changed nothing sends
such a map nothing (as with No horizon). A change goes out at once and takes no sky over. Two settings do more:

- **The moon's size** also moves the eclipse geometry, which scales with the moon's radius (`sky_model.moonLatitude`,
  `eclipseSeparation`), and keeps the night's moonlight (`surfaceMoonBrightness` times (1.6 / size)^2).
- **The night glow** scales the weather's airglow (`nightSkyBrightness`, after the image's 5 %); with the weather left
  to Remix there is none to scale.

The runtime (patch 0099) draws each image layer with its weight and colour, frees a layer's texture at 0 and loads it
again when it is turned up, and with every layer at 0 shows a night without stars, not the simulated ones.

### Following the map

The map's sun comes from:

1. the first `light_environment` of the map's BSP entity lump (lump 0, read with `file.Open`; a
   compressed lump is skipped);
2. else the first `env_sun`;
3. else `util.GetSunInfo`.

What it does with that sun:

- The time is the afternoon time at which the sun stands that high on the season's day (noon if it
  never climbs that high), and the north is turned so the sun stands where the map's does.
- A map whose sky texture (worldspawn `skyname`, else `sv_skyname`) is named for the night starts at
  23:00, with the moon where the map's light comes from.
- One named for dusk starts with the sun 3 degrees high, where the map's light comes from.
- No sun: 14:30, north 0.

### The weather

The presets' values for their 36 varying fields, blended as the runtime's blender does it:

- the blend runs over `nativeloader_weather_seconds`, eased;
- the start of a map sets them at once;
- while a weather is set, the runtime's recommended variation for that preset wanders: the cloud cover
  (±15 %) and the wind's speed (±30 %) and direction (±10 degrees), on a 300 s noise.

What GMod's scale changes. A Remix metre is 100 units (`rtx.sceneScale 1`), 1.905 real metres, so a
whole map is a few dozen Remix metres across:

- **Fog.** Each preset's fog distance comes from a visibility in real metres, 400 m (foggy) to
  13 km (clear), keeping the preset's tint: the distance at which what one sees fades to 5 %. The
  runtime reads the fog colour as sRGB and uses it linear, so the extinction is worked out from the
  linear colour. The runtime lights its froxel fog from lights only, not from the sky, so denser fog
  turns dark. The visibilities stay at 300 m or more.
- **Rain and snow** fall from 8 Remix metres around the player, 6 above, instead of 20 and 14, so
  the same particles fall near enough to be seen. Drops are 1.6 times as wide.
- **Cover.** The runtime's own test for cover (`occludeUnderCover`) traces up to 100 000 units. A
  map's 3D skybox room hangs above most maps within that and counted as cover everywhere, so no drop
  was ever born. The test is off; instead the game's trace straight up from the view decides, and
  under a roof the rain and snow fade out in half a second (by the time passed, whatever
  `nativeloader_sky_interval` is).

**Weather left to Remix** (`nativeloader_weather` empty, "(leave to Remix)" in the panel). At the
start of a map the companion then sends nothing for the weather. Cleared during a session, every
option the weather had set goes back to Remix's own value (R3-009): `rtx.conf`'s (RemixConfig's
`GetConfigVariable` reads only that file), else what Remix has without it, the package's classic layer
or the runtime's default, from [`weather_presets.lua`](../nativeloader/weather_presets.lua.md)
`defaults`. What the RTX fixes set for the map is not known here, and is not put back. A fog preset
chosen under "Remix settings" keeps its fog.

**Another add-on's later change** of an option the weather sets (or one made in the Remix menu, Alt+X)
stays until the weather's own value for it changes, or the map starts again: the companion sends a
value when its own changes, and does not take back what others set (R3-010, rejected). Only on a map
whose add-on sets the sky, once the player has taken it over, is everything put back every 10 s.

**Under the night sky image** the weather's airglow (`rtx.atmosphere.nightSkyBrightness`, 0.008 to
0.012 in the presets) goes out at 5 % of the preset's value. In Skyrim, where the image comes from,
the space between the nebulae is black. The full airglow left it slate blue and washed the image out;
the ground stays about as light, lit by the image itself
([RESEARCH.md](../../../../docs/RESEARCH.md) section 29). The simulated stars keep the full value.

**A fog preset** chosen under "Remix settings" (`nativeloader_remix_fog`,
[`nativeloader_menu.lua`](client/nativeloader_menu.lua.md)) replaces the weather's fog: the weather
then sends none of its four `rtx.volumetrics` values. It forgets what it last sent of them, so they
go out again once the preset is cleared.

## Which sky a map shows (ADR 0249)

At the map's start (`InitPostEntity`), before anything is sent, the companion reads:

- **the map**: its sky name (worldspawn `skyname`, else `sv_skyname`) and whether its faces are there
  (`materials/skybox/<name><side>.vmt` or `<name>_hdr<side>.vmt`); its `sky_camera` and scale (the entity lump); whether
  it has sky faces at all (the texinfos' `SURF_SKY`/`SURF_SKY2D` flags, lump 6). A lump the map compressed (`LZMA`) is
  unpacked through `util.Decompress` (`map_sky.lzmaStream`); one that cannot be read counts as unknown.
- **the sky files** of add-ons for this map, `data_static/nativeloader/sky/<map>/*.json` in the `GAME` path, at most
  8, each at most 16 KiB, checked by `map_sky.declaration`; a file left out is named in the console with the reason.
- **the player's choice** for the map, from `data/nativeloader_companion/sky_maps.txt`, into `nativeloader_sky_here`
  (marked as the companion's own write) and `choiceNow`, which is what the code reads: a console command runs on the
  next frame, and the map's start does not wait.

`map_sky.resolve` then gives the sky: the player's choice (`rtx`, `map` when the map has a sky of its own, else the RTX
sky; `addon`; a sky file's id), else (`auto`) the map's RTX version's (its add-on's, else the first sky file that is not
only offered; a `skybox` file only in a single-player game), else `nativeloader_sky`. The result is cached while the
choice, `nativeloader_sky` and the add-on's answer stay the same.

| Shows | When | The companion |
|---|---|---|
| The RTX sky | the default; `rtx`; `map` on a map without a sky of its own | in charge, as before |
| The map's own sky, a sky file's | `map`, a file's id, `auto` with a file, `nativeloader_sky 0` | in charge: `rtx.skyMode 0`, the 3D skybox, the sky name |
| An add-on's | `auto` or `addon` with an add-on that answers `NativeLoaderSkyOwner` | stands aside, by the rules below |
| The RTX sky until the next map | a sky or weather setting changed on a map that showed another sky | in charge (ADR 0248's take-over, kept by the user for every sky) |

- **A new choice** (`nativeloader_sky_here`, the panel's This map) is saved for the map (`auto` removes it), clears a
  take-over and shows at once, except a return to an add-on's sky that was not showing: the add-on sets its sky at the
  map's start, so the RTX sky stays until then. An unknown value is refused, the console names the choices, and the
  convar goes back.
- **`nativeloader_sky` changes** re-resolve (a map's own sky may come or go) and take nothing over.
- **The chat line**, 6 s after `InitPostEntity` (after the add-ons have said whose the sky is), once per map load, only
  with the Remix API there and "Say which sky shows" ticked (off by default, ADR 0253): `[RTX] ` and `map_sky.state`, `advice` and `limit` translated (`L`), joined by spaces;
  the console gets the English line (`[nativeloader] sky: ...`) also with `nativeloader_sky_message 0`.
- **`NATIVELOADER_SKY.takenOver()`** is also true once the player chose another sky for the map. It runs no owner hook
  (gm_stelliferous RTX asks it from its own answer to `NativeLoaderSkyOwner`); `fixed()` it may run.
- **`NATIVELOADER_SKY.mapSky()`**: `shown` (`rtx`, `own`, `addon`, `taken`), `sky`, `reason`, `threeD`, `package` (the
  title of the map's RTX version's sky), `choice`, `own`, `own3D`, `scale`, `files` (ids).
  **`NATIVELOADER_SKY.line(translate)`**: the chat line's words now.
- **The panel** (Sky and weather, from the top): a line saying what the map shows (kept current while the panel is
  open, with the 3D skybox's limit where there is one); This map (`nativeloader_sky_here`: Automatic, RTX sky, The
  map's own sky where it has one, Sky of the add-on and of each sky file), its help line, and "This map has no sky of
  its own to switch to." where it has none; Other maps (`nativeloader_sky`: RTX sky, Their own sky); Say which sky
  shows (`nativeloader_sky_message`); then a note that time of day, weather and the night sky are the RTX sky's, and
  the settings as before. The Sky choice ("Physical sky", "The map's skybox") is gone: Other maps holds its convar.

## A map whose add-on sets the sky

Some maps' RTX add-ons set the sky themselves. Modern House RTX does it on `modern_house`, and puts
it back 3, 23, 43 and 63 s after the map starts.

- **The player's own time and weather apply from the map's start** (R16, the user's item 44;
  [ADR 0105](../../../../docs/decisions/0105-the-players-sky-applies-from-a-maps-start.md)): with
  "Follow the map's sun" unticked, the companion is in charge of the sky from the start, also on such a
  map. Before R16 the add-on's sky stayed until the player changed a setting, so a chosen time and
  weather seemed not to apply until the Sky and weather panel was touched.
- **Following the map keeps such an add-on's sky** ("Follow the map's sun" ticked, the default) until
  the player changes a sky or weather setting in that session. Two settings do not count: the update
  interval and No horizon (R26), which also reaches the add-on's sky ("The horizon" above).
- **A fixed sky stays either way** ([ADR 0248](../../../../docs/decisions/0248-a-maps-add-on-keeps-a-fixed-sky.md),
  the user's answer for the gm_stelliferous remaster, 2026-11-20): an add-on whose sky belongs to the place, so
  that no time of day or weather fits it (space around a station), also answers the hook `NativeLoaderSkyFixed`
  with `true`, from the moment its Lua loads on that map. The companion then sends no sky, sun or weather at the
  map's start, also with "Follow the map's sun" unticked, until a sky or weather setting changes in the session;
  the change takes the sky over until the next map start. `NATIVELOADER_SKY.takenOver()` tells the add-on whether
  the player's sky replaces its own now, so it can stop setting its sky and remove its sun; the panel's note on
  such a map says that it keeps its sky, and `nativeloader_sky_status` adds ", fixed".
- Once the companion is in charge, its sky is put back every 10 s, and at once whenever the add-on sets
  its own again (below). The add-on's `ApplySettings` is wrapped from the sky's first tick after the
  add-on loaded (Modern House RTX loads after InitPostEntity), not only by the 10 s timer.
- **How the companion knows.** An add-on says so by answering the hook `NativeLoaderSkyOwner` with
  its name. Modern House RTX is recognised by its `MHRTX_Config` on `modern_house`.
- **When the add-on sets its sky again**, it runs the hook `NativeLoaderSkySet`, and a sky the player
  has taken over goes back in the same tick. Modern House RTX does not run it, so the companion wraps
  its `MHRTX.ApplySettings` to run it afterwards (at the start of the map, and on the 10 s timer
  whenever the function is not the wrapper: not loaded yet, or replaced by a reload of that add-on). Before R5 the player's sky waited for the 10 s timer: on `modern_house` the
  afternoon sun came up for as long as 10 s in the middle of the player's night, three times in the
  first minute, and the daylight lingered in the image's temporal history wherever the camera had
  looked, a haze over the stars with a straight edge where the view had turned (native loader review
  R5, 2026-10-31; [`night_sky_probe.lua`](../../../../tools/qa/night_sky_probe.lua.md) shows it).

## Commands

- `nativeloader_sky_time <time>`: `hh:mm`, hours, or `sunrise`, `morning`, `noon`, `afternoon`,
  `golden`, `sunset`, `dusk`, `night` (23:00) or `midnight`. Named times are sun heights on the
  season's day.
- `nativeloader_sky_status`: prints the sky, the time, the sun and moon (or the eclipse and its
  progress), the night sky and the horizon, the Night sky editor's values (two lines), the map's own sun and sky name,
  and the weather. ADR 0249 adds two lines: `this map:` the chat line's words, and `map sky:` the choice, what shows
  and why, whether the map has a sky of its own and a 3D skybox (its scale, shown or not), the sky files read
  (`id(kind skyname)`) and the engine's recorded values.
- `nativeloader_sky_here <auto|rtx|map|addon|id>`: this map's sky (ADR 0249), remembered for the map.
- `nativeloader_sky_reset`: all of these settings back to their defaults, the Night sky editor's too.
- `nativeloader_sky_night_reset`: only the Night sky editor's settings back to their defaults (its Reset button).

## Timing

- **When.** At `InitPostEntity`, then everything again 5 s later, after the RTX fixes' per-map Remix
  settings. ADR 0249: the map's own 3D skybox and sky name again 1.5 s after the start (the fixes' per-map settings
  set `r_3dsky 0` at 1 s), the chat line at 6 s, the engine's values put back at `ShutDown`.
- **Ticks.** A timer every `nativeloader_sky_interval` seconds (0.02 by default; `timer.Adjust` when the
  setting changes) runs the clock, the weather blend, the variation and the cover check.
- **A poster** ([ADR 0226](../../../../docs/decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md),
  GitHub issue 3). While the engine guard's `nlengineguard.PosterStatus()` (taken when the file loads; read only)
  says `starting` or `rendering`, a tick sends nothing and its time is dropped: the runtime's own clock stands still
  for a poster's tiles, and the sun, the moon and the weather wait with it, then go on from where they stood.
- **The panel.** `NATIVELOADER_SKY` holds the panel builders (`buildPanel`, `buildNightPanel`) and the clock for the
  panel (and tests), and `takenOver()` for a map's add-on with a fixed sky (ADR 0248).

Tested by [`tools/tests/test_companion_sky.py`](../../../../tools/tests/test_companion_sky.py.md).

Only in this machine's RTX starts ([ADR 0206](../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md)): its first line of code returns when `NativeLoaderRTXStart()`, set by `!!!!nativeloader_engine_guard.lua`, says the loader did not activate RTX (a start through an off switch, a removed loader, files a loader left behind).

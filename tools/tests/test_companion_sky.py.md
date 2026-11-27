# test_companion_sky.py

Task NC checks the archived Enhanced star-source choice through startup, live edits, reset, provider changes,
VR and map ownership. It exercises every night editor option at its native key, the image layer scales, Moon
size, disc gain and glow, shooting stars, and the isolation of physical night lighting from Standard's
Night glow. The solar eclipse tests measure the angle between the sent Sun and Moon directions at four
contact positions with two Moon sizes and two Sun sizes. Both providers' pages and the recorded Standard
option-call comparison run in the same suite.

Task H covers Mist strength on the default Partly cloudy weather, a saved look, and an in-progress blend
across the clean-air density. It checks the explicit Fog preset, clear air, the near Remix fog conversion
and release, the three map choices including saved values from round 2, and the shared slider on both pages.

Task E3 passes each complete weather row and every built-in over the library baseline through the production
editor's `check` function. A failure includes the look name and the validation reason. A session also gives one
weather a different absorption in memory, verifies the midpoint of its blend and returns to the library default.

Task E2 exercises the saved lamp-glow switch in both states at every detail level, including a conflicting
mode-table value, weather left to Remix and a Standard round trip. The editor harness covers the new haze
scale and range, the compact mixers, notice-row layout, and all five additional starting looks.

Round 2 exercises editor overrides independently of host precipitation, interrupted transitions, both Moon
settings, wetness and drying, tier-specific mode defaults, and the two mist modes. It checks the single
legacy restore and counts global volumetrics writes through desktop, VR, map ownership and shutdown.
The [editor widget harness](enhanced_editor_harness.lua.md) drives the actual page and the saved-look operations.

The horizon panel case runs the open page's update while switching Enhanced → Standard → Enhanced.
It checks that No horizon stays enabled, writes the shared Remix option in both modes, and that the
Standard Night sky selector is enabled only in Standard. The reset case also checks the horizon in
the default Enhanced mode.

The Enhanced sky cases run the real companion Lua offline on both sides of the mode switch. They compare all
Standard Remix option writes against a recording from `98b5450c`, including repeats. Calls are grouped by
action and by key because Lua does not order a table traversal. They also exercise all twelve Enhanced weather
tables, wind and precipitation, interrupted changes and release, Moon phases and eclipses, stopping and starting
the clock, a poster, loader tiers, detail overrides, fog presets, map ownership, VR and shutdown.

R20-B also loads the real defaults autorun before the sky. The new defaults scenario checks both
fresh `1`/`20` and migrated `0`/`30` profiles: one real minute advances the clock by 1.2 game hours,
while Modern House's sky remains under its add-on with zero companion writes until a player edit.
Other scenarios explicitly stop time to inspect fixed sky/weather behavior, independent of the
new moving default. The separate [QoL harness](companion_qol_harness.lua.md) checks preservation and
marker lifetime across maps/restarts.

Runs the companion's sky under LuaJIT. Two parts are tested:

- the arithmetic, [`sky_model.lua`](../../companion/nativeloader/lua/nativeloader/sky_model.lua.md);
- the session logic, [`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md),
  with the GMod functions it uses mocked: client settings and their change callbacks, the console,
  timers, hooks, the clock, `file.Open` on a made-up BSP, and the RTX fixes' `RemixConfig`, which
  records every option it is given.

The harness is written to a scratch folder under `out\tmp`.

## The arithmetic

- **The sun at latitude 40:**
  - noon heights: 50 degrees at the equinox, 73.4 in summer, 26.6 in winter;
  - sunrise and sunset: 04:30-19:30 in summer, 07:20-16:40 in winter.
- **The map's sun:** gm_construct's `light_environment` (pitch -56, yaw 306) is 56 degrees high at
  bearing 324. Following the map puts the sun exactly there, in the afternoon. A sun higher than
  summer's noon sun gives noon in its direction.
- **The moon:** at 20:00 in spring the full moon has risen opposite the set sun; the new moon has set
  with the sun.
- **The stars:** they turn 15 degrees an hour, and the pole stands at the latitude, in the north.
- **Eclipses** for a moon 0.8 degrees in radius: the stages of `eclipseSeparation` (lunar 4.64,
  2.92, 1.32 and 0 degrees at 0, 0.3, 0.7 and 1; solar 1.576, 0.024 and 0 at 0, 0.9 and 1), the
  phases an eclipse needs, and the moon's latitude without one (5.64). The moon's latitude is its
  distance from the antisolar point (full) or the sun (new), at three hours and seasons.
- **Entities:** the entity lump parser and the map's sun, from `light_environment` or `env_sun`.
- **Sky names:** night and dusk names are recognised.
- **Weather values:**
  - the blend kinds: an angle the short way round, extinction, a switch at the midpoint, colours;
  - option text;
  - `hh:mm` both ways;
  - the variation noise.

## The session

- **The start of gm_construct.** The physical sky is on (`rtx.skyMode 1`), the map's own sun is ignored
  (`rtx.ignoreGameDirectionalLights True`), the runtime's day cycle is off and the moon is on. The sun
  stands at the map's sun (56 degrees, bearing 324). The default weather, partly cloudy, is set at
  once. The time setting shows the map's time, 14:21.
- **A change of weather** to a rainstorm blends over 30 s: in between at 15 s, the preset's own values
  at 31 s.
- **Choosing a time** (`nativeloader_sky_time 18:00`) takes the sky off the map's sun. The direction
  stays the map's, and the sun moves to where the model puts it at 18:00.
- **The panel's sliders.** Writing back the map's direction rounded to whole degrees, and its time to
  two decimals, keeps the sky on the map's sun. A real move of the direction takes it off.
- **Rain under cover.** Rain falls at the preset's intensity with the runtime's cover test off. When
  the game's trace up hits a roof, it fades to nothing in half a second (and the clouds stay), and it
  comes back outside.
- **The clock.** With the time passing and a 24-minute day, 60 s is an hour, and stopping the clock
  keeps the time it reached.
- **Weather left to Remix:** nothing more is sent for it.
- **A map whose add-on sets the sky** (`MHRTX_Config` on `modern_house`): while the sky follows the map
  (the default), nothing is sent until the player changes a sky setting; then the companion takes over.
- **The player's own time on such a map** (R16; `PRESET` gives the session saved settings, here
  "Follow the map's sun" unticked, 09:48 and clear): the sky is sent at the map's start; Modern House
  RTX, loaded afterwards, is followed from the sky's next tick, and its own afternoon (21 degrees) is
  replaced in the same call by the player's sun (57.7 degrees). Without the R16 change the add-on's sun
  stays.
- **A fixed sky** (ADR 0248; `FIXED_SKY_ADDON` answers `NativeLoaderSkyOwner` and `NativeLoaderSkyFixed` from
  its load, as gm_stelliferous RTX does): with "Follow the map's sun" unticked and ticked alike, nothing is sent at
  the map's start or in the next 31 s, `NATIVELOADER_SKY.takenOver()` is false, the status line says
  "set by Station RTX, fixed" and the panel's note says that the add-on keeps its sky; a change of weather then
  takes the sky over (`rtx.skyMode 1`, overcast's cloud density 7) and `takenOver()` turns true.
- **The map's own skybox** (`nativeloader_sky 0`) gives back `rtx.skyMode 0` and the configured
  `rtx.ignoreGameDirectionalLights`.
- **A night map** (sky `sky_borealis01`) starts at 23:00, with the full moon where the map's light
  comes from.
- **Eclipses.** The start sends the eclipse geometry (`eclipseEnable`, the umbra, penumbra and sun
  scales), the moon's texture and the star map. The afternoon's full moon passes 5.64 degrees from
  the antisolar point. Choosing a lunar eclipse moves the clock to midnight (off the map's sun) and
  puts the full moon in the middle of the shadow at 100, 2.12 degrees out at 50; a solar eclipse moves
  it to noon and puts a new moon 0.71 degrees from the sun at 50. No eclipse gives back the chosen
  phase, clear of the shadow. "Procedural" turns the star map off.
- **A fog preset** (with the RTX Remix tab's [`nativeloader_menu.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_menu.lua.md)
  loaded too): Heavy Fog sets Remix's four fog values, volumetrics on and fog remapping off. A change
  of weather then blends its clouds but leaves the fog, and clearing the preset brings the weather's
  fog back at the next tick.
- **Without the Remix API** nothing is sent, also with No horizon saved ticked and ticked again.
- **No horizon** (R26, `nativeloader_sky_no_horizon`): the start of gm_construct sends
  `rtx.atmosphere.noHorizon False`; ticking it sends `True` and nothing else, and the sky still follows
  the map's sun; the status line names it; unticking sends `False`, and the reset unticks it. Saved
  ticked (`PRESET`), the start sends `True` with the physical sky.
- **No horizon on a map whose add-on sets the sky** (`MHRTX_Config` on `modern_house`): unticked, the
  start sends nothing at all; ticking it sends that option alone, and 11 s later the companion has
  still sent no `rtx.skyMode` (the add-on keeps its sky). Saved ticked, the start sends that option and
  nothing else, and unticking sends `False`.
- **The moon by day** (ADR 0207, `nativeloader_sky_moon_day`): the start of gm_construct sends
  `rtx.atmosphere.daytimeMoonBrightness 1` (as bright as the real Moon); the slider's 2.5 sends `2.5` and the sky
  still follows the map's sun; 9 is held to `4`; 0 sends `0` and the status line says "moon by day 0.00"; the reset
  sends `1` again.
- **The night sky editor** (ADR 0227, `test_the_night_sky_editor_sets_each_element`): the start of gm_construct sends
  every element at its default (the image's `0.12`, each layer's brightness and colour `1`, the simulated stars' `0.5`,
  `0.5` and `1`, the moon's `1`, `1.6` degrees, halo `15` and earthshine `0.005`, `1.2` shooting stars a minute at
  `1`); the stars' slider at 3 sends that one option and the sky still follows the map's sun; 50 is held to `8` and
  text gives the default; settings scale their options (image 2 -> `0.24`, earthshine 3 -> `0.015`, glow 0.5 -> `7.5`,
  6 shooting stars, density `0.75`). At night a moon twice as wide sends `3.2` and a quarter of the ground light, so the
  night is as light; its eclipse geometry follows its radius (clear of the shadow at (4.8 + 1) x 1.6 + 1 degrees from
  the antisolar point, half way through a lunar eclipse where `sky_model` puts it). The night glow at 2 doubles the
  weather's airglow; the status lines name the editor's values; `nativeloader_sky_night_reset` puts every element
  and the airglow back.
- **The night sky editor's page** (`test_the_night_sky_editor_page_has_a_control_for_each_element`): both pages of the
  tab built against a panel that records DForm's calls (`SCRIPT='panel'`): every editor setting has its slider over its
  own range (two decimals; the shooting stars one), with Go to night, Time passes, the Night sky choice, the section
  headings and Reset the night sky; the Sky and weather page still builds, with its help line pointing to the editor.
- **The night sky editor on a map whose add-on sets the sky**
  (`test_the_night_sky_editor_reaches_a_maps_own_sky_without_taking_it_over`): with every element at its default the
  start sends nothing; a change sends its option alone and 11 s later still no `rtx.skyMode`; a saved change
  (`PRESET`) goes out at the start, alone.

- **Which sky a map shows** (ADR 0249; `SCRIPT='mapsky'`, the BSP built by `sky_map` with a `sky_camera` and texinfos,
  `FACES`, `SKY_FILES` with `JSON`, `SAVED_CHOICES`, `ENGINE_START`, `SINGLE`; the engine's convars and the RTX fixes'
  patch switches mocked, each change logged with the fixes' warning switch as `r_3dsky`'s callback sees it):
  - `test_every_map_shows_the_rtx_sky_by_default_and_the_chat_line_says_how_to_switch`: the RTX sky and no engine
    change at the start; the chat line for a 3D skybox, a 2D sky only, missing sky textures, no sky faces; off with
    `nativeloader_sky_message 0`, the console's line still there (these scenarios start with the line ticked and its
    migration done: the harness's `LINE_DEFAULT` and `LINE_MIGRATION` start a new player's game or one saved before
    ADR 0253 instead);
  - `test_the_chat_line_is_off_by_default_and_a_saved_old_default_goes_off_once` (ADR 0253): no chat line in a new
    player's game, the console's line still there; a saved `1` from before goes to `0` once (`nativeloader_defaults.lua`,
    the marker `sky_message_client_v1.txt`); with the marker there a ticked line shows;
  - `test_this_maps_own_sky_shows_its_3d_skybox_through_the_pas_and_is_remembered`: `nativeloader_sky_here map`
    (`rtx.skyMode 0`, the map's sun back, `r_3dsky 1` between `rtx_show_3dsky_warning 0` and `1`, the PAS switches, the
    old values recorded, the choice saved), `rtx` (all put back), `auto` (the choice forgotten); the saved choice from
    the next start's first frame and its chat line; another map's choice kept in the file;
  - `test_a_map_with_a_2d_sky_only_or_a_skybox_at_another_scale_shows_its_own_sky_without_the_3d_pass`: no engine
    change, the limit said at scale 64;
  - `test_choosing_the_maps_own_sky_on_a_map_without_one_keeps_the_rtx_sky_and_says_so`, and an unknown choice refused;
  - `test_a_sky_or_weather_change_shows_the_rtx_sky_until_the_next_map`: the user's answer (ADR 0248 kept): taken, the
    engine put back, the choice kept; choosing the map's sky again shows it;
  - `test_a_maps_rtx_version_brings_a_sky_file_that_comes_above_the_rtx_sky`: a `skybox` file by priority in a
    single-player game (`sv_skyname`), the chat line naming it, `rtx` putting the map's sky name back, another file by
    its id, an offered file, the bad files left out (version, sky name, reserved id, JSON), a multiplayer game skipping
    the `skybox` file;
  - `test_a_fixed_addon_sky_stays_and_the_players_choice_for_the_map_replaces_it`: the station add-on (named only while
    its sky shows, as gm_stelliferous RTX) keeps its sky under the player's own time, `rtx` replaces it, `auto` keeps the
    RTX sky until the next map with a line saying its sky returns; a start with `rtx` saved offers its unnamed sky;
  - `test_engine_settings_an_earlier_map_changed_go_back_at_the_next_maps_start`, and `ShutDown` putting them back
    while keeping the record;
  - `test_the_sky_and_weather_page_has_this_maps_choice_and_the_one_for_other_maps`: the state line, This map's list
    (with and without the map's own sky), Other maps, Say which sky shows;
  - `test_the_map_sky_module_reads_maps_and_checks_sky_files`: `map_sky.lua` alone (names, titles, texinfo flags, the
    LZMA stream, every refusal, the order, `resolve`).

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Skipped when LuaJIT is not installed (on `PATH` or in
`%LOCALAPPDATA%\Programs\LuaJIT\bin`). Exit 0 when the tests pass or are skipped.

- `test_weather_left_to_remix_puts_back_remixs_own_values` (R3-009): after Rain, clearing the weather gives
  cloud density rtx.conf's value (the mock's) and the rain's intensity, spawn radius and lightning the
  table's defaults; nothing more is sent after that.
- In `test_a_maps_own_sky_add_on_keeps_its_sky_until_the_player_changes_it` (R3-015): the sky timer runs every
  0.02 s, `nativeloader_sky_interval 0.1` adjusts it, and that change does not take the map's sky over.

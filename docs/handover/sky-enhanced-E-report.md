# Enhanced sky editor, Task E

The desktop companion on `sky-enhanced-c` implements the [round 2 contract](sky-enhanced-round2-plan.md).
Open **RTX Remix → Sky and weather → Enhanced sky editor**. Standard stays the default. The page offers the
Enhanced switch on desktop and explains the Standard fallback in VR.

## First PoC checks

1. At 3840×2160 with GMod's normal menu scaling, open the editor in Standard. Expand Clouds, Cloud shape
   and Fog in a long-label language. Opening the page should leave My own look off. Switch to Enhanced,
   select Altostratus sheet and drag the cloud base during the two-second blend. Only that field should jump.
   Try both the slider and a typed value of 150 m for visibility. Type a near-white colour such as 0.999,0.997,0.995.
2. Save a look, load a different one and paste the first look back. Repeat after changing map. Try a pasted
   line with a missing key and one with a value outside the range. The current sky and saved settings should
   survive both. Confirm that the selected weather still determines the rain, snow or sand.
3. In a room with lamps, try Enhanced mist and Remix fog near you with the player's Alt+X volumetrics switch
   off and on. Check lamps, the flashlight, the handoff in the distance, and a fog preset chosen on the Remix
   settings page. Switch to Standard and inspect the original Alt+X switch.
4. Set rain under a low sun, then choose clear weather and watch the bow fade over five minutes. Try heavy
   snow from dry air as a control. At night compare Moon size and brightness on both skies, then adjust
   Enhanced moonlight on the ground. The reviewer owns all game sessions, visual tuning and GPU timings.

## Controls

**My own look** is `nativeloader_sky_own_look`, archived and off by default. The 45 look controls also
have individual archived convars. The third column gives their exact names. NUMOS keys in the last column
have the prefix `rtx.atmosphere.numos.`. Dimensions are in metres, kilometres, km/s or degrees as labelled.
Colours are three channels in [0,1]. Editor defaults are the tuned Partly cloudy weather.

The eight **Light and mist** controls apply to every weather and look. Sun rays also sets `rays.enable` false
at zero. Rainbow scales wetness, so its default of 1 produces zero strength in dry air. The Mist choices
are Enhanced mist (0) and Remix fog near you (1). Mode 2 of the runtime's volumetrics option is available
to the reviewer through the runtime contract.

| Group | Control | Saved setting | Range | Default | NUMOS key |
|---|---|---|---|---|---|
| Light and mist | Sun rays | `nativeloader_sky_style_rays_strength` | 0–2 | 1 | `rays.strength` |
| Light and mist | Rainbow | `nativeloader_sky_style_rainbow_strength` | 0–2 | 1 | `rainbow.strength` |
| Light and mist | Night brightness | `nativeloader_sky_style_night_gain_stops` | 0–16 | 10 | `nightGainStops` |
| Light and mist | Moonlight | `nativeloader_sky_style_moonlight_gain_stops` | -8–8 | 0 | `moonlightGainStops` |
| Light and mist | Starlight | `nativeloader_sky_style_star_gain_stops` | -8–8 | 0 | `starGainStops` |
| Light and mist | Star twinkle | `nativeloader_sky_style_star_scintillation` | 0–4 | 1 | `starScintillation` |
| Light and mist | Cloud shadows | `nativeloader_sky_style_cloud_shadow_strength` | 0–1 | 1 | `cloudShadowStrength` |
| Light and mist | Mist on the map | `nativeloader_sky_style_volumetrics` | 0–1 | 0 | `volumetrics` |
| Clouds | Cloud cover | `nativeloader_sky_look_cloud_coverage_mean` | 0–1 | 0.45 | `cloudCoverageMean` |
| Clouds | Gaps and banks | `nativeloader_sky_look_cloud_coverage_spread` | 0–1 | 0 | `cloudCoverageSpread` |
| Clouds | Cloud type | `nativeloader_sky_look_cloud_type_mean` | 0–1 | 0.7 | `cloudTypeMean` |
| Clouds | Mix of types | `nativeloader_sky_look_cloud_type_spread` | 0–1 | 0.54 | `cloudTypeSpread` |
| Clouds | Cloud density | `nativeloader_sky_look_cloud_density` | 0–60 | 20 | `cloudDensity` |
| Clouds | Cloud base (m) | `nativeloader_sky_look_cloud_base_height_meters` | 0–8000 | 1300 | `cloudBaseHeightMeters` |
| Clouds | Thickness (m) | `nativeloader_sky_look_cloud_depth_meters` | 50–10000 | 2000 | `cloudDepthMeters` |
| Clouds | Cluster size (km) | `nativeloader_sky_look_cloud_cell_size_km` | 0.5–6 | 3.65 | `cloudCellSizeKm` |
| Clouds | Cloud colour | `nativeloader_sky_look_cloud_color` | 0–1 | 0.89, 0.92, 1 | `cloudColor` |
| Cloud shape | Ragged edges | `nativeloader_sky_look_nubis3_erosion_strength` | 0–2 | 0.58 | `nubis3ErosionStrength` |
| Cloud shape | Billow size (km) | `nativeloader_sky_look_cloud_body_billow_size_km` | 0.2–4 | 1.2 | `cloudBodyBillowSizeKm` |
| Cloud shape | Fine billows | `nativeloader_sky_look_cloud_body_billow_gain` | 0–1 | 0.65 | `cloudBodyBillowGain` |
| Cloud shape | Curl (km) | `nativeloader_sky_look_cloud_curl_strength_km` | 0–1 | 0.12 | `cloudCurlStrengthKm` |
| Cloud shape | Uneven tops | `nativeloader_sky_look_cloud_column_top_variation` | 0–1 | 0.45 | `cloudColumnTopVariation` |
| Cloud shape | Soft edges | `nativeloader_sky_look_cloud_column_feather` | 0.05–1 | 0.35 | `cloudColumnFeather` |
| Cloud shape | Light in shadows | `nativeloader_sky_look_cloud_diffuse_sun_strength` | 0–1 | 0 | `cloudDiffuseSunStrength` |
| Second cloud layer | Show second layer | `nativeloader_sky_look_cloud_layer2_enable` | off/on | false | `cloudLayer2Enable` |
| Second cloud layer | Sheet cover | `nativeloader_sky_look_cloud_layer2_coverage_mean` | 0–1 | 0 | `cloudLayer2CoverageMean` |
| Second cloud layer | Sheet base (m) | `nativeloader_sky_look_cloud_layer2_base_height_meters` | -100–12000 | 5500 | `cloudLayer2BaseHeightMeters` |
| Second cloud layer | Sheet depth (m) | `nativeloader_sky_look_cloud_layer2_depth_meters` | 50–4000 | 2000 | `cloudLayer2DepthMeters` |
| Second cloud layer | Sheet shape | `nativeloader_sky_look_cloud_layer2_type_mean` | 0–1 | 0.6 | `cloudLayer2TypeMean` |
| Second cloud layer | Sheet density | `nativeloader_sky_look_cloud_layer2_density_scale` | 0–2 | 0.65 | `cloudLayer2DensityScale` |
| Second cloud layer | Sheet colour | `nativeloader_sky_look_cloud_layer2_albedo` | 0–1 | 1, 1, 1 | `cloudLayer2Albedo` |
| High ice clouds | Show cirrus | `nativeloader_sky_look_cloud_cirrus_enable` | off/on | true | `cloudCirrusEnable` |
| High ice clouds | Streak cover | `nativeloader_sky_look_cloud_cirrus_coverage_mean` | 0–1 | 0.45 | `cloudCirrusCoverageMean` |
| High ice clouds | Ice height (m) | `nativeloader_sky_look_cloud_cirrus_base_height_meters` | 1000–15000 | 9500 | `cloudCirrusBaseHeightMeters` |
| High ice clouds | Streak opacity | `nativeloader_sky_look_cloud_cirrus_optical_depth` | 0–3 | 0.33 | `cloudCirrusOpticalDepth` |
| High ice clouds | Streak angle (°) | `nativeloader_sky_look_cloud_cirrus_streak_direction` | 0–360 | 110 | `cloudCirrusStreakDirection` |
| High ice clouds | Ice halo | `nativeloader_sky_look_cloud_cirrus_halo_strength` | 0–3 | 1 | `cloudCirrusHaloStrength` |
| Wind | Drift (km/s) | `nativeloader_sky_look_cloud_wind_speed` | 0–0.1 | 0.02 | `cloudWindSpeed` |
| Wind | Drift angle (°) | `nativeloader_sky_look_cloud_wind_direction` | 0–360 | 45 | `cloudWindDirection` |
| Wind | Rise (km/s) | `nativeloader_sky_look_cloud_evolution_speed` | 0–0.02 | 0.002 | `cloudEvolutionSpeed` |
| Air | Haze density | `nativeloader_sky_look_aerosol_density` | 0–10 | 1.1 | `aerosolDensity` |
| Air | Haze colour | `nativeloader_sky_look_aerosol_tint` | 0–1 | 1, 1, 1 | `aerosolTint` |
| Air | Air density | `nativeloader_sky_look_air_density` | 0–4 | 1 | `airDensity` |
| Air | Air colour | `nativeloader_sky_look_air_tint` | 0–1 | 1, 1, 1 | `airTint` |
| Air | Ozone | `nativeloader_sky_look_ozone_density` | 0–4 | 1 | `ozoneDensity` |
| Air | Haze direction | `nativeloader_sky_look_mie_anisotropy` | -0.95–0.95 | 0.8 | `mieAnisotropy` |
| Fog | Visibility (m) | `nativeloader_sky_look_fog_visibility_meters` | 0–50000 | 20000 | `fogVisibilityMeters` |
| Fog | Thinning height (m) | `nativeloader_sky_look_fog_height_falloff_meters` | 1–3000 | 100 | `fogHeightFalloffMeters` |
| Fog | Fog base (m) | `nativeloader_sky_look_fog_base_height_meters` | -200–2000 | 0 | `fogBaseHeightMeters` |
| Fog | Fog brightness | `nativeloader_sky_look_fog_albedo` | 0–1 | 0.9 | `fogAlbedo` |
| Fog | Fog direction | `nativeloader_sky_look_fog_anisotropy` | -0.95–0.95 | 0.3 | `fogAnisotropy` |
| Fog | Shaded mist (m) | `nativeloader_sky_look_aerial_perspective_froxel_range_meters` | 100–12000 | 1000 | `aerialPerspectiveFroxelRangeMeters` |
| Storm | Strikes per minute | `nativeloader_sky_look_lightning_strikes_per_minute` | 0–60 | 0 | `lightningStrikesPerMinute` |

Two older Night sky editor controls also apply to Enhanced. `nativeloader_sky_moon_size` (0.5–5°, default
1.6°) sends `moon0.angularDiameter`. `nativeloader_sky_moon_brightness` (0–4, default 1) sends
`moonDiscGainStops` as the base-two logarithm of brightness. Zero selects the library's minimum of −16
stops. This changes the disc. The separate moonlight control adjusts illumination.

All requested look keys are present. **Shaded mist** is the additional key `aerialPerspectiveFroxelRangeMeters`.
Round 1 needed 6,000 m to remove the ring below cloud sheets, so the range travels with the look. All other
new weather fields start at their NUMOS defaults. The reviewed weather tables retain their visibility,
cirrus and cloud-sheet tuning. Performance limits live with the detail level. The existing Sky page owns
time and celestial placement. Debug, deprecated and world-scale settings are outside the editor.

## Editing and storage

**Start from** lists the twelve tuned weather looks, the four extra library looks and valid saved looks.
The [built-in data](../../companion/nativeloader/lua/nativeloader/enhanced_builtin_looks.lua) maps NUMOS
Fair, Cloudy, Altostratus and Cirrus at `41842c6` to Fair-weather cumulus, Broken cloud, Altostratus sheet
and Cirrus streaks. Each fills the complete look over the library's neutral weather baseline. Reset copies
the currently selected weather. With weather left to Remix, reset asks the player to choose a weather.

Turning My own look on or off, loading, pasting and resetting blend from the current shape over two seconds.
A drag takes effect immediately on its field, including halfway through another blend. The other fields
finish their transition. Cover and wind keep drifting. Changing weather while using a personal look still
changes precipitation. Colours have a picker and exact normalised RGB input. The visibility track devotes
its first tenth to 0–50 m, then follows a logarithmic scale to 50 km. The text box always reads metres.

One named file lives under `data/nativeloader_companion/sky_looks/<name>.json`. Names accept 1–32 ASCII
letters, digits, hyphens and underscores. Files are lowercase and Windows device names are refused.
The version-1 object has two properties, `version` and `look`. The latter has exactly the 45 look keys.
A switch must be a boolean, a number finite and in range, and a colour an array of three in-range numbers.
Duplicate, extra, missing and invalid keys reject the whole input before any convar changes. Reads are
bounded to 8 KiB. A compact JSON encoding of the default Partly cloudy look is 1,194 bytes. Save as verifies
a staged write. The page asks before replacing or deleting a file. The original can be recovered after an
interrupted replacement. A rejected file is named in the console. Clipboard sharing uses the same single-line
JSON and validator. Style, time, weather and file names stay outside the payload. The editor also rejects the
comments and trailing commas accepted by the game decoder so a shared look works with standard JSON tools.
[GMod JSON reader](https://wiki.facepunch.com/gmod/util.JSONToTable)

## Mode, mist and rain

The `mode` table in [enhanced_weather.lua](../../companion/nativeloader/lua/nativeloader/enhanced_weather.lua)
applies even when weather is left to Remix. The ten-stop default night gain and disabled haze lamps come
from the reviewer's round 1 measurements. Style controls take priority over mode values. The following
lamp budgets are starting settings for the reviewer. Lamps are off at all three levels.

| Detail | qualityLevel / rays.quality | Cutoff | Lights per tile | Lights per frame | Lamp shadows | Fade at radius |
|---|---|---:|---:|---:|---|---|
| High | 0 / 0 | 0.002 | 64 | 256 | On | Off |
| Medium | 1 / 1 | 0.005 | 16 | 64 | On | Off |
| Low | 2 / 2 | 0.01 | 8 | 32 | Off | Off |

The companion requests the runtime mist mode without writing the player's `rtx.volumetrics.enable`. The
sole migration write restores a pending round 1 `nativeloader_sky_volumetrics_saved` and clears it after
success. A fresh session makes zero such writes through mode, VR and ownership changes or shutdown.

For a handoff, the foreground fog receives a neutral sRGB transmittance corresponding to 2% linear contrast
at the current look's visibility, converted from real metres to Remix metres. Albedo and anisotropy also
match. Clear air uses white transmittance. An explicit Remix fog preset wins in both ranges. Releasing
the foreground restores the configured fog fields or package defaults, subject to the existing Lua
configuration reader. The renderer determines the handoff geometry and lighting.

Wetness follows the host rain intensity of drizzle, rain and thunderstorm. On a weather change it blends to
the incoming rain level using the weather transition. Once rain stops, the current wetness falls linearly
to zero over 300 game seconds. Changing between dry weathers does not restart drying. Snow and sand add
no wetness. The selected look can change lightning, clouds and fog independently of this value.

## Offline checks

The [sky suite](../../tools/tests/test_companion_sky.py.md) runs the production Lua and the editor's real UI
callbacks against GMod doubles. The Standard parity comparison covers 345 pre-Enhanced option writes. Editor
coverage includes first edits, loaded looks, an interrupted blend, each tier and style, the Moon controls,
both mist sources, strict file and clipboard validation, failed replacement and five-minute drying.

- `python -m unittest discover -s tools/tests -p test_companion_sky.py -q` passed all 52 tests under LuaJIT.
- `python tools/companion_i18n.py update` and `python tools/companion_i18n.py check` produced 959 companion
  texts and validated all six catalogs, plus 485 bundled add-on texts in each language.
- An offline comparison matched all 53 editor controls to the pinned NUMOS declarations or the round 2
  contract. Every default fits its control range and the control ranges respect the library's declared bounds.
- An early Release run compared two packages while an editor change was in progress. Their manifests
  differed. The final run used fixed inputs and the reproducibility check passed.
- `tools\test.ps1 -Config Release` finished with **All checks passed**. Repository conventions passed,
  CTest passed 35/35, and Python ran 29 gmapack tests (1 skipped), 26 Steam tests (1 skipped) and
  2,255 tools tests (8 skipped).

On 2026-11-26 the last native build finished at **19:05:58 UTC**. CTest finished at 19:06:50 UTC and the
entire Release suite finished at **19:11:51 UTC**.

In-game rendering, real Derma layout and performance measurements remain with the reviewer. The six
translations are agent-written and await human review.

## E2

**First reviewer check.** At 3840×2160 switch from Standard to Enhanced with the editor open. My own look
should move up immediately, before any scrolling or expanding a group. Open Air and compare haze at 1, 10,
50 and 80 in the same view. In a lamp-lit room, toggle Lamp glow in mist with the flashlight on and off and
measure each detail level.

- **Haze density** now accepts 0–100 at two decimals, including in saved and pasted looks. The thumb position is
  `log(1 + density) / log(101)`, so the common 0–10 occupies about 52% of the track. The number box reads and
  accepts density directly. The help gives landmarks for clean air at 1, a soft solar glow at 10 and white haze at 50.
- **Lamp glow in mist** is the ninth Light and mist control. Its archived convar
  `nativeloader_sky_style_aerial_perspective_local_lights` defaults to 0. It sends
  `rtx.atmosphere.numos.aerialPerspectiveLocalLights` as True or False and takes precedence over every detail
  level. Its help calls out the frame-time cost near many lamps and with the flashlight. The 45-key look
  format is unchanged. The twelve weather tables and per-level lamp limits were left to the reviewer.
- **Page layout.** The 4K capture `ui-panel2.jpg` showed the missing controls' space above My own look.
  The editor now hides their docked wrapper rows and immediately updates the layout of the form and its parent
  at startup and when the notice changes. I chose **half-height inline colour mixers** (four native font lines). All four
  pickers retain direct dragging and the exact RGB entry.
- **Start from** now lists 21 starting looks before any saved ones. Mackerel sky, Towering cumulus, Humid
  summer, High cirrus and After the rain appear after the original four library looks. Their values are the
  five E2 rows over the existing built-in baseline, ready for visual tuning.
- **Verification.** `python -m unittest discover -s tools/tests -p test_companion_sky.py -q` passed
  all 53 tests under LuaJIT. The additions cover the five E2 editor changes, including high-haze text sharing,
  immediacy of row layout and a conflicting tier lamp setting. `python tools/companion_i18n.py update` and
  `python tools/companion_i18n.py check` produced 966 complete companion texts and checked 485 bundled
  add-on texts in each of the six languages. The eight new translations per language await human review.

E2 used the reviewer's existing screenshots and offline checks. The final Release suite, new PoC captures,
frame-time measurements and visual tuning are with the reviewer. No E2 build or game session ran.

## E3

**First reviewer check.** In Enhanced → Air, keep Haze density at 40 and Haze colour white. Compare
**Haze darkness** at 1, 0.1 and 3 from the same camera, looking toward the Sun and along the horizon.
The 0.1 view should recover the milky brightness of the reviewer's `hq40p` trial. At 3 the same air should
look smokier. Then load a pre-E3 file or paste an old look while darkness is set to 3. It should return to 1
and restore the other settings from that look.

The single slider follows Haze density. It runs from 0 to 3 in 0.01 steps. One unit is NUMOS's absorption
of 0.0044 per kilometre in each channel. A setting of 0.1 sends `0.00044, 0.00044, 0.00044` to
`rtx.atmosphere.numos.mieAbsorption`. Haze colour controls the tint independently. The archived convar
`nativeloader_sky_look_mie_absorption` and the look store the native triplet. The only weather-data change
is the library default in `enhanced_weather.lua`. Every weather inherits it and can override it in its own row.

Save as and Copy now write version 2 with 46 look keys. The shared file and clipboard reader gives a version-1
look missing `mieAbsorption` the library default in memory. Opening an old file preserves its bytes. Version 2
requires the new key, and the validator checks that its three coefficients are equal, finite and within range.

The offline sky suite passed all **55 tests** under LuaJIT. It calls the production validator on all 12
weathers and nine built-ins, checks a weather override and its return to default, and exercises the slider,
native-unit round trip, old file and pasted-text migration, and rejection of malformed looks.
`python tools/companion_i18n.py update` and `check` completed with **968 companion texts** and **485 bundled
add-on texts** in each of the six languages. The two new messages per language await human review.

E3 used the reviewer's existing trial sheets. No build or game session ran. The in-game comparison and
weather tuning remain with the reviewer.

# Enhanced sky, Task C

Branch `sky-enhanced-c`, 2026-11-26. The companion implements the [round 1 contract](sky-enhanced-plan.md)
for modes 0, 1 and 2. The volumetrics readback limit below needs a reviewer decision before release.

## First check in the PoC

1. On the same map, save a Standard noon reference and frame time. Select Enhanced, confirm mode 2, then
   return to Standard and compare against the reference. Repeat with Remix volumetrics initially on and off,
   including a value changed only in Alt+X. The latter exposes the readback limit.
2. Compare the four scenes at each detail level. At fair-weather noon look for the secondary cirrus crossing
   the cumulus. With a low sun check cloud-gap rays, then the flashlight and lamps in mist. At sunset watch
   cloud tops and bases through twilight. At night compare the library Moon and stars, partial and total lunar
   eclipse, then lightning, rain and snow under cover. Tune the twelve tables from these captures and timings.
3. Select a map's own 3D skybox and a fixed-sky add-on. Change only sky quality and detail. The map keeps its
   sky. Start and stop VR with Enhanced selected on desktop. The page should explain the switch, send mode 1
   in VR, and return to mode 2 on desktop with the chosen quality.

## Settings and ownership

RTX Remix → Sky and weather → **Sky quality** saves `nativeloader_sky_enhanced` (0 Standard by default, 1
Enhanced). **Enhanced detail** saves `nativeloader_sky_enhanced_quality`. Automatic reads the loader's
schema-1 `activation.performance_tier.tier` on first use. High, Medium and Low mean NUMOS levels 0, 1 and 2.
An absent or unknown tier starts at Medium. An explicit choice wins. The eight new UI messages have entries
in all six companion catalogs.

The saved choice applies after ADR 0249 resolves which sky shows. Quality changes leave map ownership alone,
including an ADR 0248 fixed sky. VR starting, running and stopping use Standard. The companion keeps the
desktop preference and checks for session and ownership changes on its existing sky timer.
On the first Enhanced selection per map the process-local `worldChangeCount` changes, clearing NUMOS's prior
ground measurement. Switching to VR, changing detail or reapplying the sky keeps the same world number.
`nativeloader_sky_status` reports the applied Enhanced quality.

## Weather and fog

The editable rows are at the bottom of [enhanced_weather.lua](../../companion/nativeloader/lua/nativeloader/enhanced_weather.lua).
The defaults above them come from `include/numos/settings_fields.inl` and the named bases from
`src/weather.cpp` at NUMOS `41842c6`. The grey sheet values are shared by the three built-ins that use it.
The visibility column uses the existing companion's GMod distances as initial values for the library's
2% contrast distance. Every wind speed below is in km/s.

| GMod weather | NUMOS base | Visibility, m | Other GMod choices |
|---|---|---:|---|
| Clear | Clear | 13,000 | Clean air and clear cloud layers |
| Partly cloudy | PartlyCloudy | 8,800 | A high cirrus layer at 0.35 coverage with streaks at 110° across the 45° wind |
| Overcast | Overcast | 4,400 | Keeps the built-in upper sheet and shallow lower deck |
| Hazy | Haze | 1,300 | Keeps the built-in aerosol density of 4 |
| Foggy | Fog | 400 | Keeps the ground bank and slow 0.006 wind |
| Drizzle | Drizzle | 880 | Keeps the grey sheet and 0.025 wind |
| Rain | Storm | 530 | Four lightning strikes per minute from the existing rainstorm |
| Thunderstorm | Storm | 400 | Twelve strikes per minute from the existing thunderstorm |
| Snow | Overcast | 660 | Bright scattering albedo 0.98 and slower wind 0.012 |
| Blizzard | Fog | 310 | Ground bank, albedo 0.98 and wind 0.045 |
| Sandstorm | Haze | 320 | Dust tint (1, 0.79, 0.50), aerosol density 8, albedo 0.75 and wind 0.04 |
| Smog | Haze | 670 | Grey-brown tint (0.85, 0.78, 0.70), aerosol density 6, albedo 0.55 and wind 0.007 |

Cirrus, snow, blizzard, dust and smog adjustments are starting choices for visual review. Other unlisted
fields inherit their base. The direct settings use the contract prefix `rtx.atmosphere.numos.`. While a
companion weather is chosen, `weather.followGame` is false and `weather.transitionSeconds` is zero under
that prefix. `weather.preset` takes `None`, which matches none of the eleven presets and selects the direct
library settings. An empty string sent to the existing Remix setter succeeds without changing the option.
This matters when a previously selected built-in would otherwise mask the GMod values. Leaving weather to
Remix restores the configured preset, transition and weather settings. An empty starting preset and
`None` both select the library's base settings.

The weather change slider drives smoothstep interpolation from the current blend. Wind follows its shortest
arc and shares the companion's cover and wind variation. Visibility blends in reciprocal metres. The
existing host particle options carry rain, snow and sand, including the under-cover fade. The library supplies
the cloud, aerosol, lightning and height-fog settings.

NUMOS uses 52.4934 game units per metre (one GMod unit is 1.905 cm). The Remix fog picker takes precedence
over weather. Its transmittance is gamma-decoded, and the mean channel extinction converts the measuring
distance to a 2% visibility in real metres. Its mean scattering albedo and anisotropy go to height fog.
With weather left to Remix, a preset selected independently in NUMOS can supply its own weather fields
over those direct settings.

### Volumetrics readback limit

The Lua binding's [configuration reader](../../packages/fixes/licenses/oversized-skinning/memory-limits/source/remixapi/remixapi.cpp)
reads `rtx.conf` at `ConfigManager::GetConfigVariable`. It has no live option readback. On entry the
companion records the known fog-menu enable, the configured boolean, or the upstream default (true), then
sends `rtx.volumetrics.enable = False`. It restores that snapshot on Standard, map sky, loss of ownership,
VR or shutdown. A session-only client convar carries the snapshot over a client Lua restart.

A live or layered value different from those sources can be restored incorrectly. In particular, when Alt+X
has switched volumetrics off but `rtx.conf` says on, the Lua getter reports on. Exact restoration in that
case needs a live boolean readback or a scoped override owned by the runtime. The contract supplies neither.

## Time, Moon and library limits

The existing clock drives explicit sun angles, `timeOfDayHours`, day of year, latitude and north offset.
Map-follow, season, direction, named times, time passing, day length, update cadence and the poster pause
all use that clock. The library draws its NASA Moon through game moon 0 at 0.518° diameter and its catalogue
stars. This gives the Sky page's eight phases a single Moon to control. A lunar eclipse uses geometric phase and
the Sun and Earth's apparent radii at the library's mean lunar distance, reaching totality at 70% on the slider.
**Moon by day** scales the Moon's colour above the horizon and zero hides it there. NUMOS applies the
same multiplier to its light and disc.

The Standard horizon switch, Standard night editor, procedural star field, shooting stars, solar eclipse
and corona, sun dogs and extended halo arcs have no matching controls in this round. NUMOS handles its own
earthshine, lunar shadow and cirrus halo. The library has no precipitation particles, rain shafts or rainbow.
Far-sky rays beyond the near haze and the final weather tuning remain for review or later work.

## Offline verification

The companion sky harness compares complete Standard key/value calls for ten actions to pre-change
`98b5450c` (345 writes). It retains per-key order and duplicates, normalising the unspecified order of Lua table
traversal. It also exercises the new controls, all twelve weathers, transitions, ownership, VR and fog
restoration through the production Lua. A same-time Standard → Enhanced → Standard round trip compares every
previously written Standard option to its original value.

| Command from the task worktree | Result |
|---|---|
| `python -m unittest discover -s tools/tests -p test_companion_sky.py -q` | 46 tests, OK |
| `python tools/companion_i18n.py update` and `python tools/companion_i18n.py check` | 807 companion texts and 485 bundled add-on texts complete in each of the six languages |
| `tools\test.ps1 -Config Release` | Repository conventions OK. All 35 native tests passed. Python ran 29 gmapack tests (1 skipped), 26 Steam tests (1 skipped), and 2,248 tools tests (8 skipped). “All checks passed.” |

A further offline check collected the 53 distinct prefixed option keys the Lua actually sent across the
twelve weathers and the clock, Moon and fog controls. All matched the library setting list or the adapter
contract. The two new Lua modules use the ordinary rendering policy.

During a repeat Release run, the existing `nl_exit_observer_integration` test once classified its synthetic
`commit-sample` case as `crash` instead of `likely_out_of_memory`. Its isolated rerun,
`ctest --preset win64-release -R "^nl_exit_observer_integration$" -j 1`, passed (1/1).

In-game appearance, timings and weather tuning remain with the reviewer. The six translations are
agent-written and await human review.

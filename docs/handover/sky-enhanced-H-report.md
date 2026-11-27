# Less mist in the Enhanced sky, Task H

**First PoC check.** Use Enhanced, Partly cloudy, noon on `gm_construct`, with My own look off and the
Fog preset left to the weather. At **Mist 1** compare the horizon, the sun's glow and the buildings against
the reviewer's density-2 captures. Reduce Mist to zero on the Sky page. The editor should show zero too,
and the map veil should clear. Restore Mist to 1, then choose **Mist on the map → Off**. The map should be
clear while the sky retains the Partly cloudy haze. Repeat near a lamp after choosing Remix fog near you.

## Player settings

| Control | Archived client setting | Range and default |
|---|---|---|
| Mist | `nativeloader_sky_style_mist_strength` | 0–2 in 0.01 slider steps, default 1 |
| Mist on the map | `nativeloader_sky_style_volumetrics` | 0 Enhanced mist (default), 1 Remix fog near you, 2 Off |

Mist comes first in the Enhanced editor's Light and mist group. The Sky and weather page shows the same
setting below Enhanced detail while Enhanced is selected on desktop. Each page reflects edits made on the
other. Strength and map choice are styles shared by every weather and personal look. A saved or shared
look retains its authored values.

## What reaches Remix

The companion applies strength to a copy of each blended frame. For aerosol density `a` it sends
`min(a, 1.1) + max(a - 1.1, 0) * strength`. Density already below clean air stays at its original value.
Height fog interpolates in extinction. On each blended frame its visibility distance is divided by strength.
Zero strength and a starting visibility of zero both send zero visibility, the library's clear-air value.

| Mist strength | Partly cloudy aerosol density | Partly cloudy fog visibility | Map mist |
|---:|---:|---:|---|
| 0 | 1.1 | 0 (clear) | Paused, including nearby Remix fog |
| 1 | 2 | 20,000 m | Follows Mist on the map |
| 2 | 2.9 | 10,000 m | Follows Mist on the map |

At positive strength the saved map choices send the following options under `rtx.atmosphere.numos.`.

| Saved choice | `aerialPerspective` | `volumetrics` | Result |
|---|---|---:|---|
| 0 · Enhanced mist | True | 0 | Enhanced mist across the map |
| 1 · Remix fog near you | True | 1 | Nearby Remix fog when the player's Remix fog switch is on, Enhanced mist farther away |
| 2 · Off | False | 0 | Clear map, sky haze at the selected strength |

Strength zero sends False and 0 for all three choices. Raising it restores the saved choice.
The nearby fog uses the scaled visibility, and leaving the handoff releases the companion's nearby fog
overrides. An explicit Fog preset from Remix settings keeps its visibility, albedo, anisotropy and native
Remix fog values even as Mist changes. Zero and map Off still suspend the map effect. Leaving the weather
to Remix hands its weather values back as before. The Mist controls preserve the player's global
`rtx.volumetrics.enable` switch.

## Default weather

Partly cloudy now uses aerosol density 2 and inherits the library's absorption of 0.0044 per kilometre in
each channel. Its cloud shape, cirrus, wind and fog visibility retain their tuning. This is the only weather
row changed. The reviewer's saturation measurements and low-sun comparison are in the
[round 3 plan](sky-enhanced-round3-plan.md#the-new-default).

## Verification

- `python -m unittest discover -s tools/tests -p test_companion_sky.py -q` passed all 61 LuaJIT sky tests.
  They cover strength 0, 1 and 2 on weather, personal looks and a blend, clear-air and zero-fog endpoints,
  both sliders, saved map choices, nearby fog restoration and the explicit Fog preset.
- `python tools/companion_i18n.py update` and `python -X utf8 tools/companion_i18n.py check` produced
  969 complete companion texts and 485 bundled add-on texts per language. Python wrote and read back the
  six catalogs in explicit UTF-8. Across all 8,724 entries, no translation has more ASCII
  question marks than its English text. All existing translations of retained messages were preserved.
- `tools\test.ps1 -Config Release` finished with **All checks passed**. Repository conventions passed,
  CTest passed 35/35, and Python ran 29 gmapack tests (1 skipped), 26 Steam tests (1 skipped) and
  2,264 tools tests (8 skipped). On 2026-11-27 the native build finished at **04:17:48 UTC**, CTest
  finished at 04:18:27 UTC and the full suite finished at **04:23:31 UTC**.

The visual comparisons and frame-time measurements belong to the reviewer. No game session ran for Task H.

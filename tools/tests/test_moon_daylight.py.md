# test_moon_daylight.py

The regression test of the Moon by day (runtime patch 0090,
[ADR 0207](../../docs/decisions/0207-the-moon-by-day.md)): while the sun is up a moon's light is added to the sky in
front of it, as bright as the real Moon at its phase, and the night is drawn as before. Part of `tools\test.ps1` (the
`tools` folder's Python tests).

- `RuntimePatchTests.test_the_phase_laws_unit_test_from_the_patch`: takes `rtx_moon_daylight.h` and
  `tests/rtx/unit/test_moon_daylight.cpp` whole from the committed patch, compiles them with MSVC (`/std:c++17 /W4
  /WX`, as the runtime builds) under `out\tmp` and runs the test: the phase angle of a phase, the drawn Moon's
  Lommel-Seeliger and Lambert closed forms against a brute-force sum over the disc, the real Moon's law, and the day's
  scale at the companion's phases (1 full, 0.40 gibbous, 0.25 quarter, 0.15 crescent, 0.107 new), never above 1, never
  rising towards new, alike waxing and waning. Skipped without the MSVC Build Tools.
- `RuntimePatchTests.test_the_sky_adds_a_moons_light_and_hides_only_what_lies_beyond`: in `atmosphere_sky.slangh` the
  disc no longer replaces the background nor fades in with the sunset; its light is added and its coverage hides only
  what lies beyond (airglow, halos, earlier moons); its light hands over from the day's scale to the night's look with
  the old fade; the horizon cuts it unless the sky has none; the sun disc lies beyond the moons.
- `RuntimePatchTests.test_the_option_and_the_arguments`: `rtx.atmosphere.daytimeMoonBrightness` (1, 0 to 4), the
  four per-moon scales computed from each moon's phase and zeroed in the LUT cache key, one row of plain floats in
  `AtmosphereArgs`, the `RtxOptions.md` row and a translated description in all six catalogs.
- `EstimateTests`: [`moon_daylight.py`](../sky/moon_daylight.py.md)'s day scale gives the runtime's numbers; for a
  summer day under partly cloudy skies its sky stands where the decision says (0.23 around a first-quarter Moon at
  16:00) and the Moon shows within 20 % of a real Moon's contrast, well below the night's look.

```powershell
cd tools; python -m unittest tests.test_moon_daylight -v
```

Exit code: unittest's (0 when every test passes or is skipped).
